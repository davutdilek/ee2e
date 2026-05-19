# EE2E — Faz Planı ve Durum Takibi

> **Yaşayan doküman.** Her faz sonunda checkbox'lar güncellenir, kazanılan dersler "Retrospektif" bölümüne eklenir.

| Faz | Ad                                  | Durum         | Hedef Çıktı                                              |
|-----|-------------------------------------|---------------|----------------------------------------------------------|
| 0    | Hazırlık & Mimari Dokümantasyonu  | ✅ Tamamlandı   | `ARCHITECTURE.md`, `PHASES.md`, repo iskeleti           |
| 1    | Altyapı + Dockerize Backend        | ✅ Tamamlandı   | macOS↔Chrome local + ngrok üzerinden uzak istemci ile mesajlaşma doğrulandı |
| 2A   | Key Bundle Infrastructure          | ✅ Tamamlandı   | Cihazda key üretimi + sunucuda public bundle dağıtımı + atomik OPK tüketimi |
| 2B   | X3DH Handshake                     | ✅ Tamamlandı    | Alice ↔ Bob aynı `SK` türetir; safety number / fingerprint MVP |
| 3    | 1:1 E2EE Mesajlaşma                | ✅ Tamamlandı   | Double Ratchet + AES-256-GCM, gerçek şifreli mesaj      |
| 4    | Grup + Metadata Hardening          | ✅ Tamamlandı   | Sender Keys + Padding + Sealed Sender                   |
| 5    | MLS + Platform Optimizasyonları    | ✅ Tamamlandı   | TreeKEM grup, push bildirim, multi-platform             |

---

## Faz 1 — Altyapı ve Bağlantı Doğrulama

> **Tek cümlelik hedef:** *"Bir arkadaşım dünyanın başka bir yerinden uygulamamı açtığında, sunucuma bağlanabilsin, kendi odasına katılsın ve bana şifresiz de olsa bir 'Merhaba' mesajını anlık olarak ulaştırabilsin."*

### Başarı Kriteri (Definition of Done)

- [ ] `docker-compose up` ile sunucu + DB tek komutla ayağa kalkıyor
- [ ] `curl https://<ngrok-url>/health` → `{"status":"ok"}` döndürüyor
- [ ] İki Flutter istemcisi (farklı IP'lerden) bağlanıp room'a katılabiliyor
- [ ] A → B'ye gönderilen plaintext mesaj < 500 ms'de B'nin ekranına düşüyor
- [ ] B çevrimdışıysa mesaj ephemeral queue'ya düşüyor; B online olunca alıyor
- [ ] B `delivered` ack gönderdikten sonra mesaj sunucudan **silinmiş** (DB'de iz yok)
- [ ] Sunucu loglarında **HİÇBİR** mesaj içeriği görünmüyor (zero-log policy)
- [ ] Flutter UI: bağlantı durumu (Online/Offline/Reconnecting) gösteriliyor
- [ ] Flutter UI: mesaj durumu (Gönderildi ✓ / İletildi ✓✓) gösteriliyor

### İş Kırılım Yapısı (Departman Bazlı)

#### 🔧 1. DevOps / Sistem Mühendisliği

- [x] `server/Dockerfile` — Python 3.12-slim base, non-root user, multi-stage build
- [x] `server/docker-compose.yml` — `app` + `db` (postgres:16-alpine) servisleri
- [x] `.env.example` — `POSTGRES_PASSWORD`, `FLASK_SECRET`, `LOG_LEVEL`
- [x] `.gitignore` — `.env`, `*.pem`, `__pycache__/`, `.dart_tool/`, `build/`
- [x] `server/Makefile` — `make up`, `make down`, `make logs`, `make shell`, `make test-no-leak`
- [x] Healthcheck: docker-compose `healthcheck` direktifi (DB ready'ye kadar app beklesin)
- [x] Ngrok recipe — `docs/ngrok-quickstart.md`
- [ ] (Opsiyonel) GitHub Actions — `docker build` smoke test

#### 🧠 2. Backend / Yazılım Mühendisliği

- [x] `server/app/server.py` — Flask + Flask-SocketIO factory pattern
- [x] `GET /health` — DB ping dahil
- [x] Socket events:
  - [x] `connect` — `auth.client_id` ile basit auth (Faz 1)
  - [x] `disconnect` — log
  - [x] `room:join` — `room=user_id`'a katıl
  - [x] `message:send` — payload'ı recipient'in room'una emit et + offline queue
  - [x] `message:delivered` — ephemeral queue'dan kaydı sil
- [x] `server/db/schema.sql` — `users`, `key_bundles`, `one_time_prekeys` tabloları (Faz 2'ye hazır boş şema)
- [x] `server/app/ephemeral_queue.py` — in-memory dict + TTL (Faz 3'te Redis'e taşınacak)
- [x] Yapılandırılmış JSON logging — `body/ciphertext/plaintext/payload` otomatik `<redacted>`
- [ ] **Smoke test:** `make up && curl localhost:5000/health` → `{"status":"ok",...}` (Docker'lı bir ortamda manuel doğrulama bekliyor)

#### 🛡️ 3. Güvenlik Mühendisliği

- [x] TLS: ngrok otomatik HTTPS sağlar; production için `docs/tls-letsencrypt.md` (Nginx + certbot stack)
- [x] CORS politikası — `CORS_ORIGINS` env-var ile kontrol
- [x] Rate-limit: `flask-limiter` ile default 200/min
- [x] Container hardening: non-root user (uid 1001), `read_only`, `cap_drop: [ALL]`, `no-new-privileges`
- [x] Postgres dış porta açılmaz (`expose:` kullan, `ports:` değil)
- [x] Zero-log policy doğrulama: `SafeJSONFormatter` + pytest canary test + `make test-no-leak`
- [x] `docs/security-pillars.md` — 4 sütun için faz-faz uygulama

#### 🎨 4. Tasarım / UX

- [x] `client/` — manuel scaffold (`pubspec.yaml` + `lib/`); `flutter create` ile platform klasörleri eklenecek
- [x] Bağlantı durumu widget'ı: 🟢 Online / 🟡 Reconnecting / 🔴 Offline / ❌ Failed (`ConnectionIndicator`)
- [x] Basit chat UI: peer ID input + mesaj listesi + gönder butonu (`ChatScreen`)
- [x] Mesaj durumu: ⏱ Gönderiliyor → ✓ Gönderildi → ✓✓ İletildi (`MessageBubble`)
- [x] Tema: light/dark (Material 3 + system theme)
- [x] Responsive: `ConstrainedBox(maxWidth: 480)` ile desktop'ta da düzgün
- [ ] **Manuel doğrulama:** `cd client && flutter create .` (platform klasörleri için) → `flutter run`

### Faz 1 Riskleri

| Risk                                      | Olasılık | Etki   | Azaltım                                     |
|-------------------------------------------|----------|--------|---------------------------------------------|
| Ngrok ücretsiz tier kararsız              | Orta     | Düşük  | Cloudflare Tunnel veya küçük VPS hazırda    |
| Flutter SocketIO client TLS sorunları     | Düşük    | Orta   | `socket_io_client` paketi + cert validation |
| In-memory queue restart'ta veri kaybı     | Yüksek   | Düşük  | Faz 1 zaten "best-effort" — kabul edilebilir|
| Mesaj loglara sızar                       | Orta     | Yüksek | Custom logging filter + smoke test          |

### Retrospektif

**Ne iyi gitti:**
- 3 katmanlı mimari (istemci / iletişim / sunucu) baştan net çizildi → bug fix'ler hep doğru katmanda kaldı.
- Zero-log policy başından beri SafeJSONFormatter ile zorunlandı; ngrok üzerinden gerçek mesajlar geçti, loglar temiz.
- Pytest entegrasyon testleri (20/20) gerçek hatayı bulduğu yer oldu: client_msg_id eşleşmemesi, sandbox engeli vs. test öncesi kod review'da fark edilmemişti.

**Ne kötü gitti:**
- macOS Sandbox `network.client` izni atlanmıştı → "Bağlantı başarısız" → debug kayboldu, 1 saat kaybı.
- 5000 portu (AirPlay Receiver) çakışması → 5050'ye taşımak gerekti.
- Dockerfile `pip install --user` ile builder→runtime kopyalama yapıyordu ama appuser HOME farklıydı → `ModuleNotFoundError`. `PYTHONUSERBASE` ile çözüldü.
- Flutter web ngrok'tan ayrı serve edilmek istendi ama tek tünel daha pratik çıktı → backend Flutter web'i de servis ediyor.
- Sender'ın local-id'si server'ın UUID'si ile eşleşmiyordu → ✓✓ animasyonu çalışmıyordu. `client_msg_id` round-trip ile çözüldü.

**Faz 2'ye taşınacak teknik borç:**
- Auth: `client_id` query param ile basit auth — Faz 2'de IK signature ile değiştirilmeli.
- Ephemeral queue: in-memory, restart'ta veri kaybı. Faz 3'te Redis.
- Multi-tab dedup: Aynı kullanıcı iki sekmede açarsa room broadcast iki cihaza da gider — Faz 3 multi-device tasarımıyla beraber netleşecek.
- Web build production-grade değil: `flutter build web --release` kullanılıyor ama service worker yok, asset cache stratejisi yok.
- Reconnect logic agresif: `_disposed` guard eklendi ama race condition'lar tam test edilmedi.

---

## Faz 2 — Identity & Key Management

> Faz 2 iki alt faza bölündü. **2A** "anahtar dağıtım altyapısı"nı, **2B** "X3DH handshake"i kurar. Bu sayede kripto kodu tek başına izole test edilebilir, bug'lar dağılmaz.

### Kripto Kararları (Sabitlenmiş)

| Karar | Değer | Gerekçe |
|---|---|---|
| Identity DH key | **X25519** | DH için optimum; Signal standardı |
| Identity sign key | **Ed25519** | İmza için ayrı tutuluyor (eğitim/test kolaylığı) |
| Signed prekey | **X25519**, Ed25519 ile imzalanır | SPK rotation'da imza yenilenir |
| One-Time prekey | **X25519** | Tek kullanımlık, kullanılınca silinir |
| KDF | **HKDF-SHA-256** | X3DH'nin standart çıktı türetici |
| Symmetric AEAD (Faz 3) | **AES-256-GCM** | Donanım hızlandırması yaygın |
| OPK havuz boyutu | **100** | Signal pratik standardı |
| OPK fallback | **SPK-only** (DH4 atlanır) | Faz 0'da karara bağlandı |
| Wire format | **JSON** + base64url public key'ler | Faz 2'de okunabilirlik > performans |

---

## Faz 2A — Key Bundle Infrastructure

> **Tek cümlelik hedef:** *"İki istemci de cihazda kendi anahtarlarını üretir, public bundle'larını sunucuya yükler; karşı taraf bundle'ı çekebilir, OPK atomik olarak tüketilir."*

### Başarı Kriteri

- [x] `Identity` üretici: IK_dh (X25519) + IK_sig (Ed25519) + SPK (X25519, IK_sig ile imzalı) + 100 OPK (X25519)
- [x] Private key'ler `flutter_secure_storage`'da, plaintext disk'e ASLA yazılmaz
- [x] `POST /api/v1/keys/bundle` — public bundle'ı yükler (private key alanı reddedilir)
- [x] `GET /api/v1/keys/bundle/{user_id}` — bundle döner; OPK havuzunda anahtar varsa biri **atomik** olarak tüketilir + DB'den silinir
- [x] OPK havuzu boşsa fallback: bundle döner ama `one_time_prekey: null` (SPK-only mode)
- [x] Idempotent upload: aynı kullanıcı tekrar upload yaparsa SPK ve OPK güncellenir (key rotation)
- [x] SPK signature istemci tarafından IK_sig ile doğrulanabilir (test bunu kontrol eder)
- [x] Sunucu logları: hiçbir private key field'ı görmez (yoksa zaten reddedilir)
- [x] pytest: **11 yeni test** (upload happy path, fetch consume, atomic distribution, SPK-only fallback, idempotent reupload, 404, forbidden private fields, bad handle, bad length, duplicate opk_id, stats endpoint)

### İş Kırılım Yapısı

#### Server
- [x] `app/db.py` — psycopg connection helper (transaction context manager)
- [x] `app/keys_repo.py` — `upsert_bundle()`, `fetch_bundle_consuming_opk()` (FOR UPDATE SKIP LOCKED), `opk_count()`, `delete_user()`
- [x] `app/api_keys.py` — Blueprint, validation (handle regex, b64u length 32/64, forbidden private_/secret/_priv field reddi)
- [x] `app/server.py` — blueprint mount, MAX_CONTENT_LENGTH 32 KB
- [x] `tests/test_keys_api.py` — 11 test, hepsi yeşil

#### Client
- [x] `pubspec.yaml` — `cryptography: ^2.7.0`, `http: ^1.2.2`
- [x] `lib/crypto/codec.dart` — base64url encode/decode (padding'siz)
- [x] `lib/crypto/identity.dart` — `Identity` (X25519+Ed25519), `SignedPreKey`, `OneTimePreKey`, `PublicKeyBundle`, `FetchedBundle.verifySpkSignature()`
- [x] `lib/storage/secure_keys.dart` — flutter_secure_storage wrapper (identity + spk + opk havuzu, atomik OPK tüketimi)
- [x] `lib/core/keys_api.dart` — `uploadBundle()`, `fetchBundle(handle)`, `opkCount(handle)`
- [x] `lib/ui/identity_screen.dart` — Üret + Yükle + Karşı tarafı çek + İmza doğrula + Wipe; web uyarı banner'ı
- [x] `test/identity_test.dart` — 12 test: B64u, key generation, sign/verify (happy + tampered + wrong key), 100 OPK uniqueness, JSON schema, FetchedBundle parse (with/without OPK), X25519 ECDH wiring

#### Güvenlik
- [x] Server: bundle upload schema validator — sadece beklenen field'lar, byte length limits
- [x] Server: payload başına max boyut (bundle ~ 5KB; rate-limit `flask-limiter` zaten 200/min)
- [x] Client: SPK signature **indirme sonrası verify** (UI'da büyük ✅/❌ gösterilir)
- [x] Server: `forbidden_field` (private_*, *_priv, secret*) recursive reddedilir
- [x] End-to-end smoke: HTTP upload → atomic OPK consume → SPK-only fallback → 404 unknown

### Riskler

| Risk | Azaltım |
|---|---|
| Web'de `flutter_secure_storage` IndexedDB tabanlı, gerçek secure değil | "Web = demo only" notu UI'da, prod web'de kullanıcıyı uyar |
| OPK race condition (iki Alice aynı anda fetch) | DB transaction `FOR UPDATE SKIP LOCKED` ile atomik consume |
| `cryptography` Dart paketi web'de native crypto API kullanmaz | Test ortamında pure-Dart fallback yeterli; prod için `webcrypto` köprüsü Faz 3'te |

---

## Faz 2B — X3DH Handshake (Faz 2A'dan sonra)

> **Tek cümlelik hedef:** *"Alice, Bob'un bundle'ını indirir, X3DH ile `SK` türetir; Bob aynı `SK`'yı bağımsız hesaplar; eşitlik test ile doğrulanır."*

### Başarı Kriteri

- [x] `lib/crypto/x3dh.dart` — `deriveAsInitiator()`, `deriveAsResponder()`
- [x] `lib/crypto/x3dh_header.dart` — initial message header (sender_ik, sender_ek, recipient_spk_id, recipient_opk_id)
- [x] Birim test: `SK_alice == SK_bob` (her iki yönden)
- [x] Birim test: SPK-only fallback durumunda da SK eşitliği
- [x] Birim test: SPK signature geçersizse `deriveAsInitiator()` exception fırlatır
- [x] `lib/ui/safety_number_screen.dart` — fingerprint görüntüle (SHA-256(IK_a || IK_b)); MVP yeterli

### Kapsam Dışı (Faz 3'e bırakıldı)
- Mesaj şifreleme (Faz 3 Double Ratchet)
- Multi-device (Faz 3 Sesame)
- Yedekleme (Faz 5)

---

## Faz 3 — 1:1 E2EE Mesajlaşma

> **Tek cümlelik hedef:** *"Alice ve Bob, oluşturdukları ortak gizli anahtar (SK) ile Double Ratchet kurar; gönderilen her mesaj AES-256-GCM ile şifrelenir ve anahtarlar her mesajda/cevapta ileriye dönük gizlilik (Forward Secrecy) için güncellenir."*

### Başarı Kriteri

- [x] `lib/crypto/double_ratchet.dart` — KDF fonksiyonları (Root, Sender, Receiver zincirleri) ve State yönetimi.
- [x] Mesaj şifreleme ve deşifreleme (AES-256-GCM) fonksiyonları entegrasyonu.
- [x] Atlanan (out-of-order) mesajlar için "Skipped Message Keys" yönetimi.
- [x] `Session` sınıfı: X3DH ile başlar, Double Ratchet ile devam eder.
- [x] `server/app/server.py` — Sunucu sadece ciphertext'i taşıdığını doğrulamak için loglarda şifreli metni (Base64) göstermeli.
- [x] UI Entegrasyonu: Chat ekranında gerçek E2EE mesaj gönderimi ve alımı.
- [x] Testler: Alice ve Bob arası ratcheting doğrulama, mesaj sırası bozulduğunda doğru deşifre, AES-GCM şifreleme/çözme.

---

## Faz 4 — Grup Mesajlaşması & Metadata Gizliliği (Hardening)

> **Tek cümlelik hedef:** *"Kullanıcılar 1:1 yerine güvenli bir gruba mesaj atabilsin (Sender Keys) ve sunucu üzerinden giden paketler boyutundan ya da kimden kime gittiğinden hareketle (Metadata) sızıntı yapmasın (Padding & Sealed Sender)."*

### Başarı Kriteri

- [x] `lib/crypto/sender_key.dart` — Grup için Sender Key oluşturma, dağıtma ve mesaj şifreleme/çözme.
- [x] Grup oluşturma ve katılımcılara Sender Key gönderme (1:1 Double Ratchet üzerinden).
- [x] UI Entegrasyonu: `GroupChatScreen` + `GroupSession` + `GroupSessionManager`.
- [x] **Padding:** Gönderilen mesaj paketleri `MessagePadding.pad()` ile 512 byte bloklarına tamamlanır (DoubleRatchet + GroupCipher entegre).
- [x] **Sealed Sender (MVP):** `SealedSender.seal/unseal` ile sunucu göndericiyi bilemez; testler geçti.

---

## Faz 5 — MLS + Platform Optimizasyonları

> **Tek cümlelik hedef:** *"Grup şifrelemesini TreeKEM (MLS benzeri) ağaç yapısıyla ölçeklenebilir hale getir; çoklu cihaz desteği ve push bildirim altyapısını kur."*

### Başarı Kriteri

- [x] `lib/crypto/tree_kem.dart` — TreeKEM ağacı: node ekleme/silme, path secret türetme, ağaç güncellemesi (6/6 test geçti).
- [x] Bir üye eklendiğinde/çıktığında Forward Secrecy ve Post-Compromise Security korunur (testlerle doğrulandı).
- [x] `lib/crypto/multi_device.dart` — Sesame benzeri Device-Session yönetimi (MultiDeviceManager).
- [x] Push bildirim altyapısı (stub/MVP): `server/app/push.py` (sunucu kuyruk) + `lib/core/push_service.dart` (İstemci).
- [x] Testler: TreeKEM ağacında üye ekleme/silme, Forward Secrecy, Post-Compromise Security doğrulandı (27/27 tüm testler geçti).
