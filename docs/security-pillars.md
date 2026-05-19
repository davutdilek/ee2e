# Güvenlik Sütunları — Detaylı

Her sütunun **Faz başına nasıl uygulandığı** burada izlenir.

---

## 1. Zero-Knowledge

> Sunucu hiçbir private key'e veya plaintext mesaj verisine asla dokunamaz.

| Faz | Uygulama                                                                  |
|-----|---------------------------------------------------------------------------|
| 1   | Plaintext geçer (kabul edilen geçici durum) — ama loglara DÜŞMEZ          |
| 2   | Sunucu sadece **public** key bundle saklar; upload sırasında private key alanı reddedilir |
| 3   | Tüm `message:send` payload'ı şifreli; sunucuda ciphertext bile **decrypt edilemez** (anahtar yok) |
| 4   | Sealed Sender → gönderici kimliği bile şifreli                            |
| 5   | MLS commit/welcome mesajları opaque — sunucu sadece transport             |

**Doğrulama testi:** `make test-zero-knowledge` — sunucu container'ında `grep -r "<plaintext_kanaryacı>" /var/log` boş dönmeli.

---

## 2. Ephemeral Storage

> Mesajlar sunucu diskine yazılmaz; iletildiği an RAM'den/geçici DB'den temizlenir.

| Faz | Uygulama                                                                  |
|-----|---------------------------------------------------------------------------|
| 1   | In-memory dict + TTL (max 7 gün, default 24 saat); `delivered` ack ile anında sil |
| 2   | Aynı (key bundle'lar persistent ama **mesajlar değil**)                   |
| 3   | Redis'e geçiş (TTL native), `MAXMEMORY` policy = `allkeys-lru`            |
| 4   | Encrypted swap disabled, `tmpfs` mount for queue                          |
| 5   | MLS — sunucu sadece "fanout buffer", commit sonrası temizlenir            |

**Doğrulama:** Mesaj iletildikten sonra `SELECT * FROM messages` (yoksa Redis `KEYS msg:*`) → boş.

---

## 3. Forward Secrecy

> Bir anahtar çalınsa bile, geçmişte gönderilen mesajlar çözülemez.

| Faz | Uygulama                                                                  |
|-----|---------------------------------------------------------------------------|
| 1   | YOK (henüz şifreleme yok)                                                 |
| 2   | X3DH ile per-session SK; OPK her kullanımda silinir                       |
| 3   | Double Ratchet — her mesajda yeni message key türetilir, eskiler silinir  |
| 4   | Sender Keys rotation (her join/leave'de chain key reset)                  |
| 5   | MLS — TreeKEM commit'leri otomatik epoch advance + key derivation         |

**Doğrulama:** Geçmiş ciphertext + bugünkü tüm key'ler verilse bile, eski mesaj **çözülememeli**.

---

## 4. Docker Isolation

> Backend bileşenleri birbirinden ve host OS'tan izole çalışır.

| Faz | Uygulama                                                                  |
|-----|---------------------------------------------------------------------------|
| 1   | Non-root user, `cap_drop: [ALL]`, `read_only: true` (tmpfs hariç)         |
| 1   | Postgres `expose:` (sadece internal network), `ports:` YOK                |
| 1   | Custom bridge network — `app` ↔ `db` izole, dış dünyaya sadece `app:5000` |
| 3   | Redis aynı pattern: internal-only                                         |
| 4   | Rootless Docker veya Podman önerisi (production)                          |
| 5   | Secrets: docker secrets veya HashiCorp Vault (env-var değil)              |

**Doğrulama:** `docker exec app whoami` → `appuser` (root değil); `docker network inspect` → sadece `app` external.
