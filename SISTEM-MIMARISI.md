# EE2E — Sistem Mimarisi (Güncel Uygulama)

> Bu belge **şu an repoda çalışan** bileşenleri, veri akışlarını ve faz sınırlarını anlatır.  
> Uzun vadeli hedef diyagramı ve faz-ötesi vizyon için `ARCHITECTURE.md`; faz tablosu ve DoD için `PHASES.md`; TLS, tehdit modeli ve güvenlik sütunları için `docs/` altındaki ilgili dosyalara bakın.  
> **Son güncelleme:** Faz 0–1 ve **Faz 2A** tamamlandıktan sonra; Faz 2B ve sonrası burada “planlanan” olarak işaretlenir.

---

## İçindekiler

1. [Özet](#1-özet)
2. [Faz durumu (gerçek)](#2-faz-durumu-gerçek)
3. [Üç katman ve güven sınırı](#3-üç-katman-ve-güven-sınırı)
4. [Sunucu mimarisi](#4-sunucu-mimarisi)
5. [Veritabanı şeması](#5-veritabanı-şeması)
6. [Socket.IO olayları ve mesaj yaşam döngüsü](#6-socketio-olayları-ve-mesaj-yaşam-döngüsü)
7. [HTTP REST — anahtar bundle (Faz 2A)](#7-http-rest--anahtar-bundle-faz-2a)
8. [İstemci mimarisi (Flutter)](#8-istemci-mimarisi-flutter)
9. [Kriptografi (şu an ve plan)](#9-kriptografi-şu-an-ve-plan)
10. [Dağıtım, portlar ve statik web](#10-dağıtım-portlar-ve-statik-web)
11. [Güvenlik ve operasyon](#11-güvenlik-ve-operasyon)
12. [Bilinen sınırlar ve teknik borç](#12-bilinen-sınırlar-ve-teknik-borç)
13. [Kaynak dosya haritası](#13-kaynak-dosya-haritası)

---

## 1. Özet

**EE2E**, uçtan uca şifreli mesajlaşmaya giden yol haritasıyla geliştirilen bir istemci–sunucu sistemidir.

- **Bugün:** Gerçek zamanlı **Socket.IO** iletişimi (Faz 1), sunucuda **kalıcı mesaj tablosu yok**; çevrimdışı kullanıcı için **bellek içi** süreli kuyruk; Flutter ile **plaintext** sohbet doğrulaması; PostgreSQL’de **yalnızca public** anahtar materyali (Faz 2A); loglarda hassas alanların maskelenmesi.
- **Henüz yok:** X3DH ile ortak gizli anahtar (Faz 2B), Double Ratchet ve şifreli mesaj gövdesi (Faz 3), grup/MLS (Faz 4–5).

Sunucu tasarım felsefesi: **mesaj içeriğine güvenmemek** (opaque `envelope`), **private key kabul etmemek**, **mesajı DB’ye yazmamak**.

---

## 2. Faz durumu (gerçek)

| Faz | Ad | Bu belgedeki anlamı |
|-----|-----|---------------------|
| 0 | Hazırlık & dokümantasyon | `ARCHITECTURE.md`, `PHASES.md`, `docs/*` |
| 1 | Altyapı + iletim iskeleti | Docker, Flask-SocketIO, ephemeral queue, Flutter chat (şifresiz), `/health` |
| 2A | Key bundle altyapısı | `POST/GET /api/v1/keys/bundle`, atomik OPK, `Identity` + `SecureKeyStore` + `IdentityScreen` |
| 2B | X3DH | **Uygulanmadı** — ortak `SK`, ilk mesaj başlığı, safety number |
| 3+ | E2EE mesaj, grup, MLS | **Uygulanmadı** — plan `PHASES.md` ve `ARCHITECTURE.md` içinde |

---

## 3. Üç katman ve güven sınırı

```
┌─────────────────────────────────────────┐
│  İstemci (Flutter)                       │
│  UI, Socket.IO, (2A) kripto + güvenli  │
│  depolama — plaintext chat Faz 1’de    │
└──────────────────┬──────────────────────┘
                     │ TLS (ngrok/prod) + WS/polling
┌────────────────────▼──────────────────────┐
│  İletişim kanalı                            │
│  Engine.IO / Socket.IO çerçevesi            │
└────────────────────┬──────────────────────┘
                     │
┌────────────────────▼──────────────────────┐
│  Sunucu (Flask + Eventlet + Socket.IO)    │
│  Relay, RAM kuyruk, rate limit, log redact │
│  Postgres: sadece public keys (2A)       │
└───────────────────────────────────────────┘
```

**Sözleşme (hedeflenen davranış):**

| Katman | Yapar | Yapmaz (tasarım) |
|--------|--------|------------------|
| İstemci | Anahtar üretir, (2A) bundle yükler; Faz 1’de mesajı `envelope` içinde gönderir | Private key’i sunucuya göndermez (API reddeder) |
| Sunucu | Room’a relay, kuyruk, public bundle saklar | Mesaj plaintext’ini anlamaz / DB’ye mesaj yazmaz |
| DB | `users`, `key_bundles`, `one_time_prekeys` | `messages` tablosu yok |

---

## 4. Sunucu mimarisi

### 4.1 Giriş noktası

- Paket: `app` — `python -m app` veya container içi komut.
- Factory: `server/app/server.py` içinde `create_app()`.

### 4.2 HTTP (Flask)

| Yol | Açıklama |
|-----|----------|
| `GET /health` | `db` ping (PostgreSQL), `queued` kuyruk boyutu, `status`: DB up ise `ok`, değilse `503` + `degraded`. |
| `GET /` | `WEB_DIR` altında `index.html` varsa Flutter web; yoksa JSON “Hello”. |
| `GET /<path>` | Statik asset veya SPA fallback; `socket.io` ve `api/` path’leri buradan **404** (çakışmayı önlemek için). |

Blueprint: **`server/app/api_keys.py`** → önek `/api/v1/keys` (detay [§7](#7-http-rest--anahtar-bundle-faz-2a)).

### 4.3 Socket.IO

- **async_mode:** `eventlet`
- **CORS:** `CORS_ORIGINS` env ile kısıtlanabilir; aksi `*`
- **Rate limit:** `flask-limiter`, varsayılan **200 istek/dakika** (IP başına, bellek deposu). Uygulama Flask **HTTP** rotalarına bağlıdır; Socket.IO olayları ayrıca aynı limite tabi olmayabilir (ileride gerekirse Engine.IO için ayrı limit düşünülebilir).

Global **`EphemeralQueue`** örneği: `server/app/ephemeral_queue.py` — process içi, thread-safe; varsayılan TTL **24 saat**, üst sınır **7 gün**.

### 4.4 Python modülleri (özet)

| Modül | Rol |
|-------|-----|
| `server/app/server.py` | Flask + SocketIO kayıt, health, statik web, socket handler’lar |
| `server/app/api_keys.py` | Bundle JSON şeması, base64url doğrulama, yasak alan reddi |
| `server/app/keys_repo.py` | Postgres: bundle upsert, OPK atomik tüketim (`FOR UPDATE SKIP LOCKED` + `DELETE`) |
| `server/app/db.py` | `DATABASE_URL` ile psycopg bağlantı context manager |
| `server/app/ephemeral_queue.py` | `enqueue` / `drain_for` / `acknowledge` / GC |
| `server/app/logging_config.py` | JSON loglarda seçili anahtar kelimeleri `<redacted>` |

---

## 5. Veritabanı şeması

Dosya: `server/db/schema.sql`.

- **`users`:** `handle` (PK), `created_at`
- **`key_bundles`:** handle başına bir satır — `identity_dh_key` (32 B, X25519 pub), `identity_sign_key` (32 B, Ed25519 pub), `signed_prekey_id`, `signed_prekey` (32 B), `spk_signature` (64 B), zaman damgaları
- **`one_time_prekeys`:** `handle`, `opk_id`, `public_key` (32 B); `(handle, opk_id)` UNIQUE; satır **fetch ile tüketilince silinir**

**Kasıtlı olarak yok:** mesajlar, oturum plaintext’i, private key kolonları.

---

## 6. Socket.IO olayları ve mesaj yaşam döngüsü

### Bağlantı

- **`connect`:** `auth.client_id` (string) zorunlu; yoksa bağlantı reddedilir. Başarıda istemci kendi `client_id` odasına `join_room` edilir. Bekleyen mesajlar `queue.drain_for(client_id)` ile **`message:recv`** olarak gönderilir.
- **`disconnect`:** log

### Odalar

- **`room:join` / `room:leave`:** `data.room` string — genelde karşı tarafın `recipient_id` odası (sohbet hedefi).

### Mesaj

- **`message:send`:** Beklenen alanlar: `sender_id`, `recipient_id`, `envelope` (dict), isteğe bağlı `client_msg_id` (string).  
  Sunucu `relay` objesi oluşturur, `queue.enqueue(recipient, relay)` ile **her zaman** kuyruğa bir kopya koyar (`msg_id` UUID), aynı anda **`message:recv`** ile alıcı odasına emit eder; gönderenee **`message:queued`** (`msg_id`, `recipient_id`, varsa `client_msg_id`) döner.  
  **Not:** Alıcı çevrimiçi olsa bile kuyrukta bir kayıt oluşur; **`message:delivered`** ile `msg_id` acknowledge edilene kadar kuyruktan düşmez (çift teslimat riskine karşı istemci tarafında dedup kullanılır).

- **`message:delivered`:** `msg_id` (+ isteğe bağlı `sender_id`) — `queue.acknowledge`; gönderen odasına **`message:ack`**.

Sunucu `envelope` içeriğini doğrulamaz ve loglarda içerik politikası `SafeJSONFormatter` ile kısıtlanır.

---

## 7. HTTP REST — anahtar bundle (Faz 2A)

Önek: **`/api/v1/keys`**

| Metot | Yol | Davranış |
|-------|-----|----------|
| `POST` | `/bundle` | Public bundle yükler/günceller; **204** başarı. OPK listesi tamamen **yenilenir** (rotation). Gövde üst sınırı Flask `MAX_CONTENT_LENGTH` (**32 KB**). |
| `GET` | `/bundle/<handle>` | Bundle döner; varsa **bir** OPK satırı transaction içinde kilitlenir ve **silinir**; OPK yoksa `one_time_prekey: null` (**SPK-only fallback**). Bilinmeyen handle → **404**. |
| `GET` | `/bundle/<handle>/stats` | `opk_count` — geliştirme/diagnostic. |

**Handle kuralı:** `^[a-z0-9_-]{1,64}$`  
**Public key:** base64url decode sonrası **32 bayt** (X25519 / Ed25519 public).  
**İmza:** **64 bayt** (Ed25519).  
**Yasak JSON anahtarları (recursive):** Her anahtar adı küçük harfe çevrilir; içinde sırasıyla alt dizge olarak `private_`, `secret` veya `_priv` geçen alanlar reddedilir → **400** (`forbidden_field`). (Ör.: `identity_private_key`, `opk_secret`, `x_priv_y`.)

---

## 8. İstemci mimarisi (Flutter)

### 8.1 Bağımlılıklar (özet)

- `socket_io_client`, `flutter_secure_storage`, `uuid`, `intl`
- Faz 2A: `cryptography`, `http`

### 8.2 Dizin yapısı (mantıksal)

| Alan | Dosyalar (özet) |
|------|------------------|
| Giriş | `lib/main.dart`, `lib/app.dart` |
| Bağlantı | `lib/core/socket_client.dart`, `lib/core/connection_status.dart`, `lib/core/keys_api.dart` |
| Kripto (2A) | `lib/crypto/codec.dart`, `lib/crypto/identity.dart` |
| Depolama | `lib/storage/secure_keys.dart` |
| UI | `connection_screen.dart`, `chat_screen.dart`, `identity_screen.dart`, `message_bubble.dart`, `connection_indicator.dart` |

### 8.3 Akışlar

- **Faz 1 sohbet:** `ConnectionScreen` → `SocketClient` (`auth: client_id`) → `ChatScreen`. Mesaj gövdesi şu an **şifrelenmemiş** `envelope` içinde taşınır; durumlar `client_msg_id` / `msg_id` ile eşlenir.
- **Faz 2A:** Aynı ekrandan `IdentityScreen` — handle ile `Identity.generate`, `SignedPreKey.generate`, 100 `OneTimePreKey`, `SecureKeyStore` ile saklama, `KeysApi.uploadBundle`, karşı handle için `fetchBundle` + `verifySpkSignature`. Web’de güvenli depolama uyarısı gösterilir (IndexedDB ≠ donanım güvenli alanı).

---

## 9. Kriptografi (şu an ve plan)

### Şu an (2A)

- **Identity:** X25519 (`dhKeyPair`) + Ed25519 (`signKeyPair`)
- **SPK:** X25519; public bytes üzerine Ed25519 imza (`SignedPreKey`)
- **OPK:** X25519; sunucuda sadece public; istemcide private `SecureKeyStore` içinde
- **Wire:** JSON + base64url (padding’siz)

### Plan (belge / `PHASES.md` ile uyumlu)

- **2B:** X3DH, HKDF-SHA-256, ephemeral key, ilk mesaj başlığı, safety number MVP
- **3:** Double Ratchet, AES-256-GCM, opaque envelope
- **4–5:** Grup sender keys / padding / sealed sender; MLS, push

---

## 10. Dağıtım, portlar ve statik web

- **Docker Compose:** `server/docker-compose.yml` — host **`5050`** → container **`5000`** (macOS’ta 5000 çakışması nedeniyle).
- **Flutter web:** `client/build/web` → container içi **`/app/static-web`** salt okunur mount; tek origin’den API + Socket.IO + statik dosya mümkün.
- **Production TLS:** `docs/tls-letsencrypt.md` (Nginx + Let’s Encrypt önerisi).
- **Geliştirme tüneli:** `docs/ngrok-quickstart.md`

---

## 11. Güvenlik ve operasyon

- **Container:** non-root, `read_only`, `cap_drop: ALL`, `no-new-privileges`, `tmpfs` `/tmp`
- **Postgres:** compose’ta dış host portu publish edilmez; sadece ağ içi
- **Sırlar:** `.env` / `server/.env` — repoda örnek `server/.env.example`
- **Test:** `server/tests/` (pytest; Socket.IO ve keys API senaryoları), `client/test/` (Flutter)

---

## 12. Bilinen sınırlar ve teknik borç

- **Auth:** Socket.IO `client_id` — gerçek kimlik doğrulama / IK imzalı token yok (Faz 2B+ ile sıkılaştırılabilir).
- **Kuyruk:** Process belleği — restart’ta kayıp; yatay ölçekte paylaşılmaz (Faz 3’te Redis hedefi).
- **Mesaj:** Uçtan uca şifre yok; sunucu zarfı “görür” (opaque olsa da trafik analizi metadata sızdırabilir).
- **Çok sekme / çok cihaz:** Aynı `client_id` ile fanout/dedup tam çözülmedi (Faz 3 multi-device planı).
- **Web:** `flutter_secure_storage` web’de tam güvenli depolama değildir; üretim web için ek strateji gerekir.

---

## 13. Kaynak dosya haritası

| Bileşen | Konum |
|---------|--------|
| Faz planı | `PHASES.md` |
| Vizyon diyagramı (kısmen hedef) | `ARCHITECTURE.md` |
| Bu belge (güncel uygulama) | `SISTEM-MIMARISI.md` |
| DB şeması | `server/db/schema.sql` |
| Sunucu uygulama | `server/app/*.py` |
| İstemci | `client/lib/**/*.dart` |
| Güvenlik / TLS / sözlük | `docs/security-pillars.md`, `docs/threat-model.md`, `docs/glossary.md`, `docs/tls-letsencrypt.md` |

---

*Bu dosya yalnızca mimari açıklama içerir; çalıştırma komutları için `README.md`, `server/README.md`, `server/Makefile` ve `docs/ngrok-quickstart.md` kullanın.*
