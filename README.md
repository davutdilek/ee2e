# EE2E — Uçtan Uca Şifreli Mesajlaşma Sistemi

> Zero-Knowledge prensibiyle tasarlanmış, Flutter istemcisi ve Flask-SocketIO sunucusu üzerine kurulu, Signal Protokolü (X3DH + Double Ratchet) tabanlı; ileride MLS (Messaging Layer Security) ile grup şifrelemesine evrilecek bir mesajlaşma altyapısı.

## Repo Yapısı

```
ee2e/
├── ARCHITECTURE.md     ← Sistem mimarisi (yaşayan dokuman)
├── PHASES.md           ← Faz planı + durum takibi (yaşayan dokuman)
├── docs/
│   ├── security-pillars.md   ← 4 güvenlik sütunu detayları
│   ├── threat-model.md       ← Tehdit modeli (STRIDE)
│   └── glossary.md           ← Terimler sözlüğü (X3DH, OPK, IK, vs.)
├── server/             ← Flask-SocketIO + PostgreSQL + Docker (Faz 1)
└── client/             ← Flutter app — Android/iOS/macOS/Windows
```

## Mevcut Durum

**Faz 0 (Hazırlık):** ✅ Mimari ve faz planı dokümante edildi.
**Faz 1 (Altyapı + Dockerize Backend):** ⏳ Sıradaki adım.

Detaylar için `PHASES.md` dosyasına bakın.

## Teknoloji Yığını

| Katman              | Teknoloji                                          |
|---------------------|----------------------------------------------------|
| İstemci             | Flutter (Dart) + `pointycastle` + `flutter_secure_storage` |
| Gerçek-zamanlı      | Socket.IO (WebSocket Secure / `wss://`)           |
| Sunucu              | Python 3.12 + Flask + Flask-SocketIO              |
| Veritabanı          | PostgreSQL 16 (sadece **public** key bundle'lar)   |
| Konteynerizasyon    | Docker + docker-compose                           |
| Reverse Proxy / TLS | Nginx + Let's Encrypt (production)                |
| Kripto (sunucu)     | YOK — sunucu plaintext'e veya private key'e dokunmaz |

## Güvenlik Sütunlarımız (Vazgeçilmezler)

1. **Zero-Knowledge** — Sunucu, hiçbir private key'e veya plaintext mesaj verisine asla dokunamaz.
2. **Ephemeral Storage** — Mesajlar sunucu diskine yazılmaz; iletildiği an RAM'den/geçici DB'den silinir.
3. **Forward Secrecy** — Bir anahtar çalınsa bile geçmiş mesajlar çözülemez (Double Ratchet).
4. **Docker Isolation** — Backend bileşenleri birbirinden ve host OS'tan izole çalışır.
