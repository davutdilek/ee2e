"""HTTP API — Faz 2A key bundle dağıtımı.

Endpoints:
  POST /api/v1/keys/bundle
       Body:
         {
           "handle": "ali",
           "identity_dh_key":   "<b64u>",
           "identity_sign_key": "<b64u>",
           "signed_prekey_id":  7,
           "signed_prekey":     "<b64u>",
           "spk_signature":     "<b64u>",
           "one_time_prekeys": [
             {"opk_id": 1, "public_key": "<b64u>"},
             ...
           ]
         }
       Response: 204 No Content

  GET  /api/v1/keys/bundle/<handle>
       Response 200:
         {
           "handle": "ayse",
           "identity_dh_key": "<b64u>",
           "identity_sign_key": "<b64u>",
           "signed_prekey_id": 7,
           "signed_prekey": "<b64u>",
           "spk_signature": "<b64u>",
           "one_time_prekey": {"opk_id": 42, "public_key": "<b64u>"}  // ya da null
         }
       404 → kullanıcı bilinmiyor

  GET  /api/v1/keys/bundle/<handle>/stats
       Sadece dev/test: {"opk_count": N}

Validasyon kuralları:
  - handle: 1..64 ascii [a-z0-9_-]
  - public key alanları: base64url-decoded uzunluk EXACTLY 32 byte (X25519 / Ed25519)
  - spk_signature: base64url-decoded uzunluk EXACTLY 64 byte (Ed25519)
  - one_time_prekeys: 0..200 adet
  - signed_prekey_id, opk_id: 0 ≤ id < 2^31
  - Toplam JSON ≤ 32KB (rate-limit + Flask MAX_CONTENT_LENGTH)

Reddedilenler:
  - "private_*" / "secret*" / "*_priv" anahtarları içeren payload → 400
"""
from __future__ import annotations

import base64
import binascii
import re
from typing import Any

from flask import Blueprint, jsonify, request

from . import keys_repo

bp = Blueprint("keys_api", __name__, url_prefix="/api/v1/keys")

_HANDLE_RE = re.compile(r"^[a-z0-9_-]{1,64}$")
_PUBKEY_LEN = 32
_SIG_LEN = 64
_MAX_OPKS = 200
_MAX_INT32 = (1 << 31) - 1
_FORBIDDEN_KEY_PREFIXES = ("private_", "secret", "_priv")


class _BadRequest(Exception):
    def __init__(self, code: str, msg: str = "") -> None:
        self.code = code
        self.msg = msg


def _b64u_decode_fixed(value: Any, expected_len: int, field: str) -> bytes:
    if not isinstance(value, str):
        raise _BadRequest("bad_type", f"{field} must be string")
    try:
        # urlsafe base64; padding'i tolere et
        padded = value + "=" * (-len(value) % 4)
        raw = base64.urlsafe_b64decode(padded.encode("ascii"))
    except (binascii.Error, ValueError):
        raise _BadRequest("bad_b64", f"{field} not valid base64url")
    if len(raw) != expected_len:
        raise _BadRequest(
            "bad_length",
            f"{field} expected {expected_len} bytes, got {len(raw)}",
        )
    return raw


def _b64u_encode(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode("ascii")


def _validate_handle(value: Any) -> str:
    if not isinstance(value, str) or not _HANDLE_RE.match(value):
        raise _BadRequest("bad_handle", "handle must match [a-z0-9_-]{1,64}")
    return value


def _validate_int(value: Any, field: str) -> int:
    if not isinstance(value, int) or isinstance(value, bool):
        raise _BadRequest("bad_type", f"{field} must be int")
    if value < 0 or value > _MAX_INT32:
        raise _BadRequest("bad_range", f"{field} out of range")
    return value


def _reject_forbidden_keys(obj: Any) -> None:
    """Recursive: payload'da private_*/secret*/_priv anahtarı varsa 400."""
    if isinstance(obj, dict):
        for k, v in obj.items():
            if not isinstance(k, str):
                continue
            lk = k.lower()
            for prefix in _FORBIDDEN_KEY_PREFIXES:
                if prefix in lk:
                    raise _BadRequest(
                        "forbidden_field",
                        f"payload must not contain '{k}' (private material is client-only)",
                    )
            _reject_forbidden_keys(v)
    elif isinstance(obj, list):
        for item in obj:
            _reject_forbidden_keys(item)


@bp.errorhandler(_BadRequest)
def _on_bad_request(e: _BadRequest):  # type: ignore[no-untyped-def]
    return jsonify({"error": e.code, "message": e.msg}), 400


@bp.post("/bundle")
def upload_bundle() -> Any:
    payload = request.get_json(silent=True)
    if not isinstance(payload, dict):
        raise _BadRequest("bad_json", "expected JSON object")

    _reject_forbidden_keys(payload)

    handle = _validate_handle(payload.get("handle"))
    identity_dh_key = _b64u_decode_fixed(
        payload.get("identity_dh_key"), _PUBKEY_LEN, "identity_dh_key"
    )
    identity_sign_key = _b64u_decode_fixed(
        payload.get("identity_sign_key"), _PUBKEY_LEN, "identity_sign_key"
    )
    signed_prekey_id = _validate_int(payload.get("signed_prekey_id"), "signed_prekey_id")
    signed_prekey = _b64u_decode_fixed(
        payload.get("signed_prekey"), _PUBKEY_LEN, "signed_prekey"
    )
    spk_signature = _b64u_decode_fixed(
        payload.get("spk_signature"), _SIG_LEN, "spk_signature"
    )

    raw_opks = payload.get("one_time_prekeys", [])
    if not isinstance(raw_opks, list):
        raise _BadRequest("bad_type", "one_time_prekeys must be array")
    if len(raw_opks) > _MAX_OPKS:
        raise _BadRequest("too_many_opks", f"max {_MAX_OPKS}")
    seen_ids: set[int] = set()
    opks: list[keys_repo.OneTimePreKey] = []
    for entry in raw_opks:
        if not isinstance(entry, dict):
            raise _BadRequest("bad_opk_entry", "each opk must be object")
        opk_id = _validate_int(entry.get("opk_id"), "opk.opk_id")
        if opk_id in seen_ids:
            raise _BadRequest("duplicate_opk_id", f"opk_id {opk_id} repeated")
        seen_ids.add(opk_id)
        opks.append(
            keys_repo.OneTimePreKey(
                opk_id=opk_id,
                public_key=_b64u_decode_fixed(
                    entry.get("public_key"), _PUBKEY_LEN, "opk.public_key"
                ),
            )
        )

    keys_repo.upsert_bundle(
        handle=handle,
        identity_dh_key=identity_dh_key,
        identity_sign_key=identity_sign_key,
        signed_prekey_id=signed_prekey_id,
        signed_prekey=signed_prekey,
        spk_signature=spk_signature,
        one_time_prekeys=opks,
    )
    return ("", 204)


@bp.get("/bundle/<handle>")
def fetch_bundle(handle: str) -> Any:
    handle = _validate_handle(handle)
    bundle = keys_repo.fetch_bundle_consuming_opk(handle)
    if bundle is None:
        return jsonify({"error": "not_found"}), 404

    body: dict[str, Any] = {
        "handle": bundle.handle,
        "identity_dh_key": _b64u_encode(bundle.identity_dh_key),
        "identity_sign_key": _b64u_encode(bundle.identity_sign_key),
        "signed_prekey_id": bundle.signed_prekey_id,
        "signed_prekey": _b64u_encode(bundle.signed_prekey),
        "spk_signature": _b64u_encode(bundle.spk_signature),
        "one_time_prekey": None,
    }
    if bundle.one_time_prekey is not None:
        body["one_time_prekey"] = {
            "opk_id": bundle.one_time_prekey.opk_id,
            "public_key": _b64u_encode(bundle.one_time_prekey.public_key),
        }
    return jsonify(body)


@bp.get("/bundle/<handle>/stats")
def bundle_stats(handle: str) -> Any:
    handle = _validate_handle(handle)
    return jsonify({"opk_count": keys_repo.opk_count(handle)})
