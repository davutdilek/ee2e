"""SafeJSONFormatter — hassas alanları sızdırmaz."""
from __future__ import annotations

import json
import logging

from app.logging_config import REDACTED, SafeJSONFormatter


def _format(extra: dict) -> dict:
    formatter = SafeJSONFormatter()
    record = logging.LogRecord(
        name="test", level=logging.INFO, pathname=__file__, lineno=1,
        msg="event", args=(), exc_info=None,
    )
    record.extra = extra
    return json.loads(formatter.format(record))


def test_redacts_body_field():
    out = _format({"body": "Merhaba dünya", "ok": True})
    assert out["extra"]["body"] == REDACTED
    assert out["extra"]["ok"] is True


def test_redacts_ciphertext_and_plaintext():
    out = _format({"ciphertext": "AAA", "plaintext": "BBB"})
    assert out["extra"]["ciphertext"] == REDACTED
    assert out["extra"]["plaintext"] == REDACTED


def test_redacts_nested_sensitive_keys():
    out = _format({"envelope": {"body": "secret stuff", "msg_id": "x"}})
    assert out["extra"]["envelope"]["body"] == REDACTED
    assert out["extra"]["envelope"]["msg_id"] == "x"


def test_msg_id_is_safe_to_log():
    out = _format({"msg_id": "abc-123", "from": "alice", "to": "bob"})
    assert out["extra"]["msg_id"] == "abc-123"
    assert out["extra"]["from"] == "alice"


def test_canary_string_in_body_does_not_leak():
    canary = "EE2E_CANARY_PLAINTEXT"
    out = _format({"body": canary})
    serialized = json.dumps(out)
    assert canary not in serialized
