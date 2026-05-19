"""Socket.IO entegrasyon testleri (eventlet client/server in-process).

Faz 1 başarı kriterlerinin otomatize doğrulaması:
  - İki istemci aynı sunucuya bağlanır
  - A → B mesaj relay olur (B online iken)
  - B offline iken mesaj queue'lanır, B bağlandığında alır
  - delivered ack queue'dan siler
  - Loglara mesaj içeriği DÜŞMEZ
"""
from __future__ import annotations

import io
import json
import logging
import threading
import time

import pytest
import socketio as sio_client
from flask import Flask

from app.ephemeral_queue import EphemeralQueue
from app.logging_config import SafeJSONFormatter
from app.server import create_app, queue, socketio


@pytest.fixture(scope="module")
def server_url():
    app: Flask = create_app()
    queue._by_recipient.clear()
    queue._by_id.clear()

    server_thread = threading.Thread(
        target=lambda: socketio.run(app, host="127.0.0.1", port=5555,
                                    allow_unsafe_werkzeug=True),
        daemon=True,
    )
    server_thread.start()
    time.sleep(0.6)
    yield "http://127.0.0.1:5555"


def _make_client(client_id: str, url: str):
    received: list[dict] = []
    c = sio_client.Client(reconnection=False)

    @c.on("message:recv")
    def _recv(data):
        received.append(data)

    c.connect(url, auth={"client_id": client_id}, wait_timeout=5)
    c.received_messages = received
    return c


def test_health_endpoint(server_url):
    import urllib.request
    with urllib.request.urlopen(f"{server_url}/health", timeout=2) as r:
        assert r.status in (200, 503)
        body = json.loads(r.read())
        assert "status" in body and "queued" in body


def test_a_to_b_online_relay(server_url):
    a = _make_client("alice-online", server_url)
    b = _make_client("bob-online", server_url)
    time.sleep(0.2)

    a.emit("message:send", {
        "sender_id": "alice-online",
        "recipient_id": "bob-online",
        "envelope": {"ciphertext": "ZW5jcnlwdGVkX2hlbGxv"},
    })
    time.sleep(0.3)

    assert len(b.received_messages) == 1
    rcvd = b.received_messages[0]
    assert rcvd["sender_id"] == "alice-online"
    assert rcvd["envelope"]["ciphertext"] == "ZW5jcnlwdGVkX2hlbGxv"
    assert "msg_id" in rcvd

    a.disconnect()
    b.disconnect()


def test_offline_recipient_gets_queued_on_connect(server_url):
    a = _make_client("alice-q", server_url)
    a.emit("message:send", {
        "sender_id": "alice-q",
        "recipient_id": "bob-offline",
        "envelope": {"ciphertext": "QUFB"},
    })
    time.sleep(0.2)

    b = _make_client("bob-offline", server_url)
    time.sleep(0.4)

    assert len(b.received_messages) == 1
    assert b.received_messages[0]["envelope"]["ciphertext"] == "QUFB"

    a.disconnect()
    b.disconnect()


def test_delivered_ack_removes_from_queue(server_url):
    a = _make_client("alice-ack", server_url)
    a.emit("message:send", {
        "sender_id": "alice-ack",
        "recipient_id": "bob-ack-offline",
        "envelope": {"ciphertext": "QkJC"},
    })
    time.sleep(0.2)
    size_before = queue.size()
    assert size_before >= 1

    b = _make_client("bob-ack-offline", server_url)
    time.sleep(0.3)
    msg_id = b.received_messages[0]["msg_id"]
    b.emit("message:delivered", {"msg_id": msg_id, "sender_id": "alice-ack"})
    time.sleep(0.2)

    drained_again = queue.drain_for("bob-ack-offline")
    assert drained_again == []

    a.disconnect()
    b.disconnect()


def test_connect_rejected_without_client_id(server_url):
    c = sio_client.Client(reconnection=False)
    with pytest.raises(Exception):
        c.connect(server_url, wait_timeout=3)


def test_no_plaintext_leak_to_logs(server_url, caplog):
    canary = "EE2E_CANARY_PLAINTEXT_DO_NOT_LEAK"

    buf = io.StringIO()
    handler = logging.StreamHandler(buf)
    handler.setFormatter(SafeJSONFormatter())
    root = logging.getLogger()
    root.addHandler(handler)

    try:
        a = _make_client("alice-leak", server_url)
        b = _make_client("bob-leak", server_url)
        time.sleep(0.2)
        a.emit("message:send", {
            "sender_id": "alice-leak",
            "recipient_id": "bob-leak",
            "envelope": {"body": canary, "ciphertext": canary},
        })
        time.sleep(0.3)
        a.disconnect()
        b.disconnect()
    finally:
        root.removeHandler(handler)

    logs = buf.getvalue()
    assert canary not in logs, "Plaintext canary leaked to logs!"
