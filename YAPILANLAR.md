# EE2E — Yapılanlar

> Bu belge **tamamlanmış işleri** özetler. Ayrıntılı faz tablosu ve checkbox’lar için `PHASES.md`; güncel mimari için `SISTEM-MIMARISI.md` kullanılır.  
> **Son güncelleme:** Faz 0, 1 ve 2A tamamlandıktan sonra.

---

## Özet tablo

| Faz | Ad | Durum |
|-----|-----|--------|
| 0 | Hazırlık & Mimari Dokümantasyonu | Tamamlandı |
| 1 | Altyapı + Dockerize Backend + iletim doğrulaması | Tamamlandı |
| 2A | Key Bundle Infrastructure | Tamamlandı |

---

## Faz 0 — Hazırlık ve dokümantasyon

- Üç katmanlı mimari ve faz planının yazılması: `ARCHITECTURE.md`, `PHASES.md`.
- Güvenlik ilkeleri ve tehdit modeli dokümanları: `docs/security-pillars.md`, `docs/threat-model.md`, `docs/glossary.md`.
- Operasyon rehberleri: `docs/ngrok-quickstart.md`, `docs/tls-letsencrypt.md`.
- Repo yapısı: `server/` ve `client/` ayrımı, `.gitignore`, örnek ortam dosyaları.

---

## Faz 1 — Altyapı ve iletim (şifreleme öncesi)

**Amaç:** Uzak istemcilerin aynı sunucuya bağlanıp gerçek zamanlı mesaj alışverişi yapabilmesi; mesaj içeriğinin sunucuda **kalıcı olarak saklanmaması**; loglarda hassas alanların maskelenmesi.

### Sunucu

- **Docker:** `server/Dockerfile` (Python 3.12, non-root, multi-stage), `server/docker-compose.yml` (`app` + Postgres 16), Makefile komutları.
- **Uygulama:** `server/app/server.py` — Flask factory, Flask-SocketIO (eventlet), `GET /health` (DB ping + kuyruk boyutu).
- **Socket.IO:** `connect` (`auth.client_id`), `disconnect`, `room:join` / `room:leave`, `message:send` (relay + kuyruk + `client_msg_id` round-trip), `message:delivered` (ack, kuyruktan silme).
- **Ephemeral kuyruk:** `server/app/ephemeral_queue.py` — process içi, TTL (varsayılan 24 saat, üst sınır 7 gün), thread-safe.
- **Loglama:** `server/app/logging_config.py` — JSON formatter ile `body` / `plaintext` / `ciphertext` vb. redaksiyon.
- **Statik web:** Flutter `build/web` container’a mount; tek origin’den web + API + Socket.IO.

### Veritabanı (Faz 1 sonrası şema hazır)

- `server/db/schema.sql` — `users`, `key_bundles`, `one_time_prekeys` (Faz 2A’da kullanıma geçti). **Mesaj tablosu yok.**

### Güvenlik ve sertleştirme

- CORS (`CORS_ORIGINS`), `flask-limiter` (ör. 200/dk), container `read_only`, `cap_drop: ALL`, Postgres’in host’a port publish edilmemesi.
- Pytest: ephemeral kuyruk, log redaksiyonu, Socket.IO relay senaryoları (mesaj içeriği loga sızmaz).

### İstemci (Flutter)

- Bağlantı: `SocketClient`, `ConnectionStatus`, `ConnectionIndicator`.
- Sohbet: `ConnectionScreen`, `ChatScreen`, `MessageBubble` (gönderiliyor / gönderildi / iletilildi), `client_msg_id` ile sunucu `msg_id` eşlemesi.
- Platform: Android / iOS / macOS / web; macOS ağ izinleri (entitlements).

### Pratik doğrulama

- Yerel ve ngrok üzerinden iki istemci ile mesajlaşma doğrulandı (plaintext iletim).

---

## Faz 2A — Public anahtar dağıtımı

**Amaç:** Kimlik ve ön-anahtarların cihazda üretilmesi; sunucuda **yalnızca public** materyalin tutulması; OPK’nın **atomik** tüketilmesi; OPK bitince **SPK-only** fallback.

### Kripto (istemci)

- `Identity`: X25519 (DH) + Ed25519 (imza).
- `SignedPreKey`: X25519, Ed25519 ile imzalı.
- `OneTimePreKey`: 100 adet batch üretim.
- `PublicKeyBundle` / `FetchedBundle` ve SPK imza doğrulaması (`verifySpkSignature`).

### Depolama ve API

- `SecureKeyStore` — `flutter_secure_storage` ile private materyal; OPK tüketiminde yerel havuzdan silme.
- `KeysApi` — `POST /api/v1/keys/bundle`, `GET .../bundle/<handle>`, istatistik endpoint’i.

### Sunucu

- `api_keys.py`, `keys_repo.py`, `db.py` — şema doğrulama, yasak alan reddi (anahtar adında `private_`, `secret`, `_priv` alt dizgisi; bkz. `SISTEM-MIMARISI.md` §7), `FOR UPDATE SKIP LOCKED` ile OPK silme.
- Pytest: bundle yükleme, fetch ile tüketim, SPK-only, idempotent upload, 404, validation testleri.

### UI

- `IdentityScreen` — kimlik üret, bundle yükle, karşı tarafı çek, imzayı doğrula; web için “demo only” uyarısı.

---

## Bu belgenin kapsam dışı bıraktığı şeyler

- **Henüz yok:** X3DH, Double Ratchet, gerçek E2EE mesaj gövdesi, grup, MLS — bunlar `YAPILACAKLAR.md` içindedir.
- **Faz 1 checklist’te açık kalan maddeler:** `PHASES.md` içinde bazı DoD satırları hâlâ `[ ]` (ör. opsiyonel CI, manuel smoke notları); **faz tamamlandı** sayılsa da takip için oraya bakılabilir.

---

*Detaylı iş kırılımı ve retrospektif: `PHASES.md`.*
