"""Faz 2A — Key bundle API testleri.

Gerçek Postgres + Flask test client kullanır. `make test` ile container içinde
çalıştırılır (DATABASE_URL DB'yi gösterir).
"""
from __future__ import annotations

import base64
import os
import uuid

import pytest

from app import keys_repo
from app.server import create_app


def _b64u(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode("ascii")


def _make_bundle(handle: str, opk_count: int = 3) -> dict:
    return {
        "handle": handle,
        "identity_dh_key": _b64u(b"\x11" * 32),
        "identity_sign_key": _b64u(b"\x22" * 32),
        "signed_prekey_id": 7,
        "signed_prekey": _b64u(b"\x33" * 32),
        "spk_signature": _b64u(b"\x44" * 64),
        "one_time_prekeys": [
            {"opk_id": i, "public_key": _b64u(bytes([0x50 + i]) * 32)}
            for i in range(1, opk_count + 1)
        ],
    }


@pytest.fixture()
def client():
    if not os.environ.get("DATABASE_URL"):
        pytest.skip("DATABASE_URL not set; key bundle tests need real Postgres")
    app = create_app()
    app.config.update(TESTING=True)
    with app.test_client() as c:
        yield c


@pytest.fixture()
def handle():
    h = f"test-{uuid.uuid4().hex[:10]}"
    yield h
    try:
        keys_repo.delete_user(h)
    except Exception:
        pass


def test_upload_then_fetch_consumes_opk(client, handle):
    payload = _make_bundle(handle, opk_count=3)
    r = client.post("/api/v1/keys/bundle", json=payload)
    assert r.status_code == 204

    assert keys_repo.opk_count(handle) == 3

    r = client.get(f"/api/v1/keys/bundle/{handle}")
    assert r.status_code == 200
    data = r.get_json()
    assert data["handle"] == handle
    assert data["signed_prekey_id"] == 7
    assert data["one_time_prekey"] is not None
    assert data["one_time_prekey"]["opk_id"] in {1, 2, 3}

    assert keys_repo.opk_count(handle) == 2


def test_fetch_after_opk_pool_drained_returns_null_opk(client, handle):
    client.post("/api/v1/keys/bundle", json=_make_bundle(handle, opk_count=2))
    client.get(f"/api/v1/keys/bundle/{handle}")
    client.get(f"/api/v1/keys/bundle/{handle}")
    assert keys_repo.opk_count(handle) == 0

    r = client.get(f"/api/v1/keys/bundle/{handle}")
    assert r.status_code == 200
    data = r.get_json()
    assert data["one_time_prekey"] is None  # SPK-only fallback


def test_idempotent_upload_replaces_opks(client, handle):
    client.post("/api/v1/keys/bundle", json=_make_bundle(handle, opk_count=5))
    assert keys_repo.opk_count(handle) == 5

    new_payload = _make_bundle(handle, opk_count=2)
    new_payload["signed_prekey_id"] = 99
    r = client.post("/api/v1/keys/bundle", json=new_payload)
    assert r.status_code == 204

    assert keys_repo.opk_count(handle) == 2
    r = client.get(f"/api/v1/keys/bundle/{handle}")
    assert r.get_json()["signed_prekey_id"] == 99


def test_fetch_unknown_returns_404(client):
    r = client.get("/api/v1/keys/bundle/nobody-here-xyz")
    assert r.status_code == 404
    assert r.get_json()["error"] == "not_found"


def test_atomic_opk_consume_distributes_unique_keys(client, handle):
    """Aynı bundle'a ardışık 3 fetch → 3 farklı OPK döndürmeli."""
    client.post("/api/v1/keys/bundle", json=_make_bundle(handle, opk_count=3))

    seen_ids: set[int] = set()
    for _ in range(3):
        r = client.get(f"/api/v1/keys/bundle/{handle}")
        opk = r.get_json()["one_time_prekey"]
        assert opk is not None
        seen_ids.add(opk["opk_id"])

    assert seen_ids == {1, 2, 3}
    assert keys_repo.opk_count(handle) == 0


def test_rejects_private_key_field(client, handle):
    bad = _make_bundle(handle)
    bad["identity_private_key"] = _b64u(b"\xff" * 32)
    r = client.post("/api/v1/keys/bundle", json=bad)
    assert r.status_code == 400
    assert r.get_json()["error"] == "forbidden_field"


def test_rejects_nested_secret_field(client, handle):
    bad = _make_bundle(handle)
    bad["one_time_prekeys"][0]["opk_secret"] = "leak"
    r = client.post("/api/v1/keys/bundle", json=bad)
    assert r.status_code == 400


def test_rejects_bad_handle(client):
    bad = _make_bundle("Has Caps And Spaces!")
    r = client.post("/api/v1/keys/bundle", json=bad)
    assert r.status_code == 400
    assert r.get_json()["error"] == "bad_handle"


def test_rejects_short_public_key(client, handle):
    bad = _make_bundle(handle)
    bad["identity_dh_key"] = _b64u(b"\x00" * 16)  # 16 bytes, expected 32
    r = client.post("/api/v1/keys/bundle", json=bad)
    assert r.status_code == 400
    assert r.get_json()["error"] == "bad_length"


def test_rejects_duplicate_opk_id(client, handle):
    bad = _make_bundle(handle, opk_count=2)
    bad["one_time_prekeys"][1]["opk_id"] = bad["one_time_prekeys"][0]["opk_id"]
    r = client.post("/api/v1/keys/bundle", json=bad)
    assert r.status_code == 400
    assert r.get_json()["error"] == "duplicate_opk_id"


def test_stats_endpoint(client, handle):
    client.post("/api/v1/keys/bundle", json=_make_bundle(handle, opk_count=4))
    r = client.get(f"/api/v1/keys/bundle/{handle}/stats")
    assert r.status_code == 200
    assert r.get_json()["opk_count"] == 4
