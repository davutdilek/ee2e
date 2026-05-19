"""
Push Notification Kuyruğu (MVP/Stub) — Faz 5

Gerçek FCM/APNs entegrasyonu yerine in-memory kuyruk.
Üretim ortamında Celery + Redis veya Cloud Tasks ile değiştirilir.
"""

import logging
import time
from dataclasses import dataclass, field
from typing import Optional

log = logging.getLogger("ee2e.push")


@dataclass
class PushToken:
    user_id: str
    device_id: str
    token: str
    platform: str  # 'ios' | 'android' | 'web'
    registered_at: float = field(default_factory=time.time)


@dataclass
class PushPayload:
    recipient_user_id: str
    notification_type: str  # 'new_message' | 'key_update' | 'group_invite' | 'device_added'
    title: str = ""
    body: str = ""
    data: dict = field(default_factory=dict)
    created_at: float = field(default_factory=time.time)


class PushService:
    """In-memory push notification servisi (stub)."""

    def __init__(self):
        self._tokens: dict[str, list[PushToken]] = {}  # user_id -> [PushToken]
        self._queue: list[PushPayload] = []

    def register_token(self, token: PushToken) -> None:
        """Kullanıcının push token'ını kaydeder."""
        if token.user_id not in self._tokens:
            self._tokens[token.user_id] = []

        # Aynı device_id varsa güncelle
        existing = [t for t in self._tokens[token.user_id] if t.device_id == token.device_id]
        if existing:
            self._tokens[token.user_id].remove(existing[0])

        self._tokens[token.user_id].append(token)
        log.info("push token registered", extra={"extra": {
            "user_id": token.user_id,
            "device_id": token.device_id,
            "platform": token.platform,
        }})

    def unregister_token(self, user_id: str, device_id: str) -> None:
        """Bir cihazın push token'ını kaldırır."""
        if user_id in self._tokens:
            self._tokens[user_id] = [
                t for t in self._tokens[user_id] if t.device_id != device_id
            ]

    def get_tokens(self, user_id: str) -> list[PushToken]:
        """Bir kullanıcının tüm push token'larını döndürür."""
        return self._tokens.get(user_id, [])

    def enqueue(self, payload: PushPayload) -> int:
        """Bildirim kuyruğuna ekler. Kuyruktaki toplam sayıyı döndürür."""
        self._queue.append(payload)
        log.info("push enqueued", extra={"extra": {
            "recipient": payload.recipient_user_id,
            "type": payload.notification_type,
        }})
        return len(self._queue)

    def process_queue(self) -> list[dict]:
        """
        Kuyruktaki tüm bildirimleri işler (stub: sadece loglar).
        Gerçek implementasyonda FCM/APNs HTTP çağrıları yapılır.
        Döndürülen liste: işlenen her bildirim için sonuç dict'i.
        """
        results = []
        while self._queue:
            payload = self._queue.pop(0)
            tokens = self.get_tokens(payload.recipient_user_id)
            for token in tokens:
                # Stub: Gerçek push gönderimi yerine log
                log.info("push sent (stub)", extra={"extra": {
                    "to_device": token.device_id,
                    "platform": token.platform,
                    "type": payload.notification_type,
                }})
                results.append({
                    "device_id": token.device_id,
                    "status": "sent_stub",
                    "type": payload.notification_type,
                })
        return results

    def queue_size(self) -> int:
        return len(self._queue)

    def clear(self) -> None:
        self._tokens.clear()
        self._queue.clear()


# Singleton
push_service = PushService()
