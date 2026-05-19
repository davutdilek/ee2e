# EE2E — Sistem Mimarisi

> **Yaşayan doküman.** Her faz sonunda güncellenir. Son güncelleme: Faz 0 (Hazırlık).

---

## 1. Üç Katmanlı Genel Yapı

```
┌──────────────────────────────────────────────────────────────────┐
│                    İSTEMCİ KATMANI (Flutter)                     │
│  ┌─────────────────┐  ┌──────────────────┐  ┌─────────────────┐  │
│  │  Key Management │  │  Crypto Engine   │  │  Local Storage  │  │
│  │  IK / SPK / OPK │  │  X3DH + Ratchet  │  │  Secure Storage │  │
│  └─────────────────┘  └──────────────────┘  └─────────────────┘  │
│                              │  ▲                                │
│                  (yalnızca   │  │   plaintext                    │
│                   şifreli    │  │   ASLA çıkmaz)                 │
│                   payload)   ▼  │                                │
└──────────────────────────────│──│────────────────────────────────┘
                               │  │
                          wss://│  │ wss://   (TLS 1.3)
                               ▼  │
┌──────────────────────────────────────────────────────────────────┐
│                İLETİŞİM KATMANI (Socket.IO / WSS)                │
│         "Kör" iletim — sadece zarfı taşır, içeriği görmez        │
└──────────────────────────────│──│────────────────────────────────┘
                               ▼  │
┌──────────────────────────────────────────────────────────────────┐
│              SUNUCU KATMANI (Docker / Flask)                     │
│  ┌─────────────────┐  ┌──────────────────┐  ┌─────────────────┐  │
│  │ SocketIO Router │  │  Key Bundle API  │  │  Ephemeral Q.   │  │
│  │ (room-based)    │  │  (HTTP REST)     │  │  (RAM, TTL)     │  │
│  └─────────────────┘  └──────────────────┘  └─────────────────┘  │
│           │                    │                                 │
│           ▼                    ▼                                 │
│  ┌──────────────────────────────────────┐                        │
│  │   PostgreSQL — sadece PUBLIC keys    │                        │
│  │   (IK_pub, SPK_pub + sig, OPK_pub[]) │                        │
│  └──────────────────────────────────────┘                        │
└──────────────────────────────────────────────────────────────────┘
```

### Katman Sözleşmeleri

| Katman    | NE yapar                                       | NE yapamaz                                    |
|-----------|------------------------------------------------|-----------------------------------------------|
| İstemci   | Anahtar üretir, şifreler, çözer, yerel saklar | Private key'i sunucuya YOLLAYAMAZ            |
| İletişim  | Şifreli zarfı taşır, room routing yapar       | Zarfı AÇAMAZ (TLS dışında erişim yok)        |
| Sunucu    | Public bundle saklar, mesajı yönlendirir      | Plaintext'e DOKUNAMAZ, mesajı KALICI saklamaz|

---

## 2. Veri Akışı: İlk Mesaj (Ali → Ayşe)

```
1. Kayıt    : Ali ve Ayşe — IK, SPK(+sig), OPK[1..100] üret → public bundle'ları
              POST /api/v1/keys/bundle ile sunucuya yükle.

2. X3DH     : Ali, Ayşe henüz çevrimdışıyken bile mesaj atmak ister.
              GET /api/v1/keys/bundle/{ayse_id} → Ayşe'nin (IK_pub, SPK_pub, sig, OPK_pub_i)
              Sunucu o OPK'yı tüketildi olarak işaretler ("Used Once").
              Ali, X3DH ile Shared Secret SK türetir.

3. Encrypt  : Ali, Double Ratchet'i SK ile başlatır → AES-GCM ile mesajı şifreler.
              Header: { sender_id, recipient_id, ratchet_pub, n, pn, opk_id_used }
              Body  : ciphertext (Base64)

4. Transmit : socket.emit('message:send', envelope) → Sunucu room('ayse_id')'a relay eder.
              Ayşe online ise → anında push, sunucu RAM'den siler.
              Offline ise → ephemeral queue'ya TTL ile koyulur (max 7 gün).

5. Decrypt  : Ayşe alır → header'daki opk_id ile aynı X3DH'i tersinden çalıştırır →
              SK türetir → Ratchet'i başlatır → ciphertext'i çözer → ekrana basar.
              Sunucuya 'message:delivered' ack gönderir → sunucu kaydı SİLER.
```

---

## 3. Bileşen Sorumlulukları (Faz Bazlı)

### Faz 1 — Skeleton (mevcut hedef)
- `server/app.py` → Flask + Flask-SocketIO; `/health`, `connect`, `join_room`, `message` event'leri
- `server/Dockerfile`, `docker-compose.yml` → tek komutla up
- `server/db/schema.sql` → `users`, `key_bundles`, `one_time_prekeys` tabloları (boş, sadece şema)
- `client/` → Flutter scaffold; bağlantı durumu UI (online/offline/reconnecting); plaintext "merhaba" gönder

### Faz 2 — Identity & Handshake
- `client/lib/crypto/identity.dart` → IK (Ed25519), SPK (X25519), OPK[] üret
- `client/lib/crypto/x3dh.dart` → X3DH kütüphanesi
- `server/api/keys.py` → bundle upload/download REST endpoint'leri

### Faz 3 — 1:1 E2EE + Multi-device + Local Encrypted History
- `client/lib/crypto/ratchet.dart` → Double Ratchet
- `client/lib/crypto/aead.dart` → AES-256-GCM
- `client/lib/crypto/sesame.dart` → Multi-device session yönetimi
- `client/lib/storage/sqlcipher.dart` → şifreli yerel mesaj geçmişi
- `server/sockets/relay.py` → ack-on-delivery + delete; multi-device fanout

### Faz 4 — Gruplar + Metadata Hardening
- `client/lib/crypto/sender_keys.dart` → WhatsApp-tarzı Sender Keys
- Padding (örn. tüm mesajlar 256-byte multiple'a yuvarlanır)
- Sealed Sender (gönderici kimliği şifrelenir)

### Faz 5 — MLS + Platform
- `client/lib/crypto/mls/` → TreeKEM tabanlı grup
- Push notification adaptörleri (APNs, FCM, WNS)

---

## 4. Tehdit Modeli (Özet — detay: `docs/threat-model.md`)

| Tehdit                       | Karşı Önlem                                         |
|------------------------------|-----------------------------------------------------|
| Sunucu ele geçirilir         | Zero-Knowledge: zaten plaintext yok                 |
| MitM (ağ dinlemesi)          | TLS 1.3 (wss://) + cert pinning (Faz 4)            |
| Geçmiş anahtarlar sızar      | Forward Secrecy (Double Ratchet)                    |
| Replay saldırısı             | Ratchet sayaçları (n, pn) + per-message nonce       |
| Metadata sızıntısı           | Sealed Sender + Padding (Faz 4)                     |
| Kötü niyetli istemci         | SPK signature doğrulama, OPK exhaustion rate-limit  |
| Cihaz çalınması              | `flutter_secure_storage` (Keychain/Keystore) + biyometri |

---

## 5. Bağlantı Stratejisi (Faz 1)

- **Geliştirme**: `localhost:5000` + `ngrok http 5000` → arkadaşlar test edebilir.
- **Production (Faz 1 sonu)**: VPS (1 vCPU/1 GB yeterli) + Nginx + Let's Encrypt → `wss://ee2e.example.com`.
- Container portları: sadece `5000` (internal) → Nginx 443'e map'ler. PostgreSQL portu **dışarıya açılmaz**.

---

## 6. Tasarım Kararları

- [x] **OPK fallback**: SPK-only (Signal modeli). OPK havuzu tükenince yeni session SPK'dan türetilir; tek seferlik anahtar olmamasının güvenlik etkisi belgelenir, istemci background'da OPK havuzunu yeniler.
- [x] **Multi-device**: Faz 3'te Sesame protokolü ile. Her cihaz ayrı IK + bundle, kullanıcı = `device_set`.
- [x] **Mesaj geçmişi**: Cihazda yerel olarak **SQLCipher** ile şifreli sakla (anahtar `flutter_secure_storage`'da). Cloud backup yok (Faz 5'te opsiyonel olarak değerlendirilir).
- [ ] MLS'e geçiş Faz 4 grup yapısını tamamen değiştirecek — migration stratejisi (Faz 4 başında karara bağlanacak).
