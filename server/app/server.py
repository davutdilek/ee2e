"""Flask + Flask-SocketIO uygulama factory.

Faz 1 kapsamı:
  - GET /health           → DB ping dahil
  - SocketIO connect      → client_id query param ile basit auth (geçici)
  - SocketIO room:join    → kendi user_id room'una katıl
  - SocketIO message:send → recipient room'una relay et + offline ise queue'la
  - SocketIO message:delivered → ephemeral queue'dan sil

Faz 1'de plaintext payload taşınabilir; Faz 3'ten itibaren payload her zaman
opaque ciphertext olur. Sunucu içeriğe HİÇBİR fazda bakmaz.
"""
from __future__ import annotations

import logging
import os
from typing import Any

import psycopg
from flask import Flask, jsonify, send_from_directory
from flask_cors import CORS
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address
from flask_socketio import SocketIO, emit, join_room, leave_room

from .api_keys import bp as keys_bp
from .ephemeral_queue import EphemeralQueue
from .logging_config import configure_logging

log = logging.getLogger("ee2e.server")
WEB_INDEX = "index.html"

socketio = SocketIO(
    cors_allowed_origins="*",
    async_mode="eventlet",
    logger=False,
    engineio_logger=False,
)

queue = EphemeralQueue()


def _db_ping() -> bool:
    dsn = os.environ.get("DATABASE_URL")
    if not dsn:
        return False
    try:
        with psycopg.connect(dsn, connect_timeout=2) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT 1")
                cur.fetchone()
        return True
    except Exception as exc:
        log.warning("db ping failed", extra={"extra": {"err": str(exc)}})
        return False


def create_app() -> Flask:
    configure_logging()

    app = Flask(__name__)
    app.config["SECRET_KEY"] = os.environ.get("FLASK_SECRET", "dev-only-change-me")
    app.config["JSON_SORT_KEYS"] = False
    app.config["MAX_CONTENT_LENGTH"] = 32 * 1024  # 32 KB; bundle ~5 KB
    web_dir = os.environ.get("WEB_DIR", "/app/static-web")
    app.register_blueprint(keys_bp)

    cors_origins = os.environ.get("CORS_ORIGINS", "*")
    if cors_origins != "*":
        origins_list = [o.strip() for o in cors_origins.split(",")]
        socketio.cors_allowed_origins = origins_list
        CORS(app, origins=origins_list)
    else:
        CORS(app)

    Limiter(
        get_remote_address,
        app=app,
        default_limits=["200 per minute"],
        storage_uri="memory://",
    )

    @app.get("/health")
    def health() -> Any:
        db_ok = _db_ping()
        status = "ok" if db_ok else "degraded"
        return jsonify({"status": status, "db": db_ok, "queued": queue.size()}), (200 if db_ok else 503)

    @app.get("/")
    def index() -> Any:
        index_path = os.path.join(web_dir, WEB_INDEX)
        if os.path.exists(index_path):
            return send_from_directory(web_dir, WEB_INDEX)
        return jsonify({"service": "ee2e", "phase": 1, "msg": "Hello, encrypted world."})

    @app.get("/<path:path>")
    def web_app(path: str) -> Any:
        if path.startswith("socket.io") or path.startswith("api/"):
            return jsonify({"error": "not_found"}), 404
        file_path = os.path.join(web_dir, path)
        if os.path.exists(file_path) and os.path.isfile(file_path):
            return send_from_directory(web_dir, path)
        index_path = os.path.join(web_dir, WEB_INDEX)
        if os.path.exists(index_path):
            return send_from_directory(web_dir, WEB_INDEX)
        return jsonify({"error": "not_found"}), 404

    socketio.init_app(app)
    _register_socket_handlers()
    return app


def _client_id_from_auth(auth: Any) -> str | None:
    if isinstance(auth, dict):
        cid = auth.get("client_id")
        if isinstance(cid, str) and cid.strip():
            return cid.strip()
    return None


def _register_socket_handlers() -> None:

    @socketio.on("connect")
    def on_connect(auth: Any = None) -> bool:
        client_id = _client_id_from_auth(auth)
        if not client_id:
            log.info("rejected connect: missing client_id")
            return False
        join_room(client_id)
        log.info("connected", extra={"extra": {"client_id": client_id}})
        pending = queue.drain_for(client_id)
        for env in pending:
            emit("message:recv", env)
        return True

    @socketio.on("disconnect")
    def on_disconnect() -> None:
        log.info("disconnected")

    @socketio.on("room:join")
    def on_room_join(data: dict[str, Any]) -> None:
        room = data.get("room") if isinstance(data, dict) else None
        if isinstance(room, str) and room:
            join_room(room)
            emit("room:joined", {"room": room})

    @socketio.on("room:leave")
    def on_room_leave(data: dict[str, Any]) -> None:
        room = data.get("room") if isinstance(data, dict) else None
        if isinstance(room, str) and room:
            leave_room(room)
            emit("room:left", {"room": room})

    @socketio.on("message:send")
    def on_message_send(data: dict[str, Any]) -> None:
        if not isinstance(data, dict):
            emit("error", {"code": "bad_payload"})
            return
        recipient = data.get("recipient_id")
        sender = data.get("sender_id")
        envelope = data.get("envelope")
        client_msg_id = data.get("client_msg_id")
        if not (isinstance(recipient, str) and isinstance(sender, str)
                and isinstance(envelope, dict)):
            emit("error", {"code": "bad_payload"})
            return

        relay = {
            "sender_id": sender,
            "recipient_id": recipient,
            "envelope": envelope,
        }
        msg_id = queue.enqueue(recipient, relay)
        relay["msg_id"] = msg_id

        emit("message:recv", relay, to=recipient)
        ack_payload: dict[str, Any] = {"msg_id": msg_id, "recipient_id": recipient}
        if isinstance(client_msg_id, str):
            ack_payload["client_msg_id"] = client_msg_id
        emit("message:queued", ack_payload)
        log.info(
            "relayed",
            extra={"extra": {"msg_id": msg_id, "from": sender, "to": recipient}},
        )

    @socketio.on("message:delivered")
    def on_message_delivered(data: dict[str, Any]) -> None:
        msg_id = data.get("msg_id") if isinstance(data, dict) else None
        sender = data.get("sender_id") if isinstance(data, dict) else None
        if not isinstance(msg_id, str):
            return
        removed = queue.acknowledge(msg_id)
        if isinstance(sender, str):
            emit("message:ack", {"msg_id": msg_id, "removed": removed}, to=sender)
        log.info("acked", extra={"extra": {"msg_id": msg_id, "removed": removed}})
