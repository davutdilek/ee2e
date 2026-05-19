"""Yapılandırılmış JSON logger + plaintext sızıntı engelleyici.

Zero-Knowledge prensibimizin loglara yansıması: hiçbir mesaj `body` alanı
loga yazılmaz. SafeFormatter, "body" / "ciphertext" / "plaintext" gibi
anahtarları otomatik olarak `<redacted>` ile değiştirir.
"""
from __future__ import annotations

import json
import logging
import os
import sys
from typing import Any

REDACTED = "<redacted>"
SENSITIVE_KEYS = frozenset({"body", "plaintext", "ciphertext", "payload",
                            "private_key", "secret"})


def _scrub(obj: Any) -> Any:
    if isinstance(obj, dict):
        return {k: (REDACTED if k in SENSITIVE_KEYS else _scrub(v))
                for k, v in obj.items()}
    if isinstance(obj, (list, tuple)):
        return [_scrub(x) for x in obj]
    return obj


class SafeJSONFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        payload: dict[str, Any] = {
            "ts": self.formatTime(record, "%Y-%m-%dT%H:%M:%S%z"),
            "level": record.levelname,
            "logger": record.name,
            "msg": record.getMessage(),
        }
        extra = getattr(record, "extra", None)
        if isinstance(extra, dict):
            payload["extra"] = _scrub(extra)
        if record.exc_info:
            payload["exc"] = self.formatException(record.exc_info)
        return json.dumps(payload, ensure_ascii=False)


def configure_logging() -> None:
    level = os.environ.get("LOG_LEVEL", "INFO").upper()
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(SafeJSONFormatter())
    root = logging.getLogger()
    root.handlers.clear()
    root.addHandler(handler)
    root.setLevel(level)
