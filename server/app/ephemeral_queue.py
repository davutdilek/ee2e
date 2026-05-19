"""In-memory ephemeral message queue.

Faz 1 implementasyonu: process-local dict + TTL.
Restart'ta veri kaybı *kabul edilebilir* — Faz 1'in başarı kriterlerinden biri
de zaten "sunucu hiçbir şeyi kalıcı saklamaz" prensibinin somut tezahürü.

Faz 3'te Redis'e taşınacak (TTL native, multi-replica, persistence opsiyonel).
"""
from __future__ import annotations

import threading
import time
import uuid
from collections import defaultdict
from dataclasses import dataclass, field
from typing import Any

DEFAULT_TTL_SECONDS = 24 * 3600
MAX_TTL_SECONDS = 7 * 24 * 3600


@dataclass
class QueuedEnvelope:
    msg_id: str
    recipient_id: str
    envelope: dict[str, Any]
    expires_at: float = field(default_factory=lambda: time.time() + DEFAULT_TTL_SECONDS)


class EphemeralQueue:
    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._by_recipient: dict[str, list[QueuedEnvelope]] = defaultdict(list)
        self._by_id: dict[str, QueuedEnvelope] = {}

    def enqueue(self, recipient_id: str, envelope: dict[str, Any],
                ttl_seconds: int = DEFAULT_TTL_SECONDS) -> str:
        ttl = max(1, min(ttl_seconds, MAX_TTL_SECONDS))
        msg_id = str(uuid.uuid4())
        item = QueuedEnvelope(
            msg_id=msg_id,
            recipient_id=recipient_id,
            envelope={**envelope, "msg_id": msg_id},
            expires_at=time.time() + ttl,
        )
        with self._lock:
            self._by_recipient[recipient_id].append(item)
            self._by_id[msg_id] = item
        return msg_id

    def drain_for(self, recipient_id: str) -> list[dict[str, Any]]:
        now = time.time()
        with self._lock:
            items = self._by_recipient.pop(recipient_id, [])
            envelopes: list[dict[str, Any]] = []
            for item in items:
                if item.expires_at >= now:
                    envelopes.append(item.envelope)
                self._by_id.pop(item.msg_id, None)
            return envelopes

    def acknowledge(self, msg_id: str) -> bool:
        with self._lock:
            item = self._by_id.pop(msg_id, None)
            if item is None:
                return False
            try:
                self._by_recipient[item.recipient_id].remove(item)
            except ValueError:
                pass
            return True

    def gc_expired(self) -> int:
        now = time.time()
        removed = 0
        with self._lock:
            for rid, items in list(self._by_recipient.items()):
                kept = [i for i in items if i.expires_at >= now]
                removed += len(items) - len(kept)
                for i in items:
                    if i.expires_at < now:
                        self._by_id.pop(i.msg_id, None)
                if kept:
                    self._by_recipient[rid] = kept
                else:
                    self._by_recipient.pop(rid, None)
        return removed

    def size(self) -> int:
        with self._lock:
            return len(self._by_id)
