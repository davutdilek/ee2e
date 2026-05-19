# EE2E — Yapılacaklar

> Bu belge **henüz yapılmamış veya planlanan** işleri sırayla listeler. Resmi faz tablosu için `PHASES.md` kullanılır.  
> **Son güncelleme:** Faz 2B–5 beklemede iken yazıldı.

---

## Özet: kalan fazlar

| Sıra | Faz | Ad | Kısa hedef |
|------|-----|-----|------------|
| 1 | **2B** | X3DH Handshake | İki tarafın aynı `SK`’yı türetmesi; ilk mesaj başlığı; safety number MVP |
| 2 | **3** | 1:1 E2EE Mesajlaşma | Double Ratchet + AES-256-GCM; sunucuya sadece ciphertext |
| 3 | **4** | Grup + Metadata Hardening | Sender Keys, padding, sealed sender |
| 4 | **5** | MLS + Platform | TreeKEM / MLS tarzı grup, push, optimizasyon |

---

## Faz 2B — X3DH Handshake

**Bağımlılık:** Faz 2A (bundle üretimi ve dağıtımı) tamam.

### Hedef

- Alice, Bob’un public bundle’ını kullanarak **ortak gizli `SK`** türetsin; Bob aynı `SK`’yı bağımsız hesaplasın.
- İlk oturum için **header** (ör. gönderen ephemeral, SPK/OPK id’leri) tanımlansın.
- **Safety number / fingerprint** MVP (ör. `SHA-256(IK_a || IK_b)` veya eşdeğer karşılaştırılabilir gösterim).

### Örnek iş maddeleri

- [ ] `lib/crypto/x3dh.dart` — `deriveAsInitiator()`, `deriveAsResponder()` (HKDF-SHA-256 ile `SK`).
- [ ] `lib/crypto/x3dh_header.dart` — initial message header yapısı.
- [ ] Birim testler: `SK_alice == SK_bob`; OPK yokken (SPK-only) eşitlik; geçersiz SPK imzasında hata.
- [ ] `lib/ui/safety_number_screen.dart` (veya mevcut ekrana entegre) — kullanıcıya gösterilebilir fingerprint.

### Kapsam dışı (bilinçli)

- Mesajın tam şifreli taşınması → **Faz 3** (Double Ratchet).
- Multi-device oturum birleştirme → **Faz 3** (Sesame vb. plan).
- Bulut yedekleme → **Faz 5** plan notlarında.

---

## Faz 3 — 1:1 uçtan uca şifreli mesajlaşma

**Bağımlılık:** Faz 2B (`SK` ve oturum başlatma).

### Hedef

- Socket.IO üzerinden taşınan `envelope` gövdesi **AEAD ile şifreli** (hedef: AES-256-GCM).
- **Double Ratchet** ile forward secrecy ve mesaj sırası güvenliği.
- Sunucu mesaj içeriğini çözemez (opaque blob); mevcut relay/ack mimarisi korunur veya sıkılaştırılır.

### Planlı / mimaride geçen ekler

- Multi-device (Sesame veya eşdeğer strateji).
- Yerel şifreli mesaj geçmişi (ör. SQLCipher), bulutta plaintext yedek yok.
- Ephemeral kuyruk: ölçek için **Redis** (TTL, çok instance) değerlendirmesi (`PHASES.md` retrospektif borç).

---

## Faz 4 — Grup ve metadata sertleştirme

**Bağımlılık:** Faz 3’te stabil 1:1 E2EE.

### Hedef (özet)

- Grup mesajlaşması için **Sender Keys** (veya seçilen grup modeli).
- **Padding** ile trafik analizi zorlaştırma.
- **Sealed sender** benzeri metadata koruması (tasarıma göre aşamalı).

### Not

- `ARCHITECTURE.md` içinde MLS’e geçişin Faz 4 grup yapısını etkileyebileceği notu var; Faz 4 başında migration kararı netleştirilmeli.

---

## Faz 5 — MLS ve platform

**Bağımlılık:** Faz 4 veya paralel planlama.

### Hedef (özet)

- **MLS / TreeKEM** tarzı grup anahtar yönetimi (mimari hedef).
- Push bildirimleri (APNs, FCM, WNS vb.).
- Çok platformlu üretim sertleştirmesi (özellikle web anahtar depolama stratejisi).

---

## Faz 1–2A’dan taşınan teknik borç (çapraz işler)

Bunlar ayrı bir “faz” değil; ilgili fazda ele alınmalı:

| Konu | Not |
|------|-----|
| Socket auth | `client_id` ile basit auth → güçlü kimlik / imza (2B sonrası veya 3 ile uyumlu) |
| In-memory kuyruk | Restart’ta kayıp; yatay ölçek yok → Redis (Faz 3 civarı) |
| Çok sekme / fanout | Aynı kullanıcıda dedup ve cihaz modeli → Faz 3 multi-device |
| Web güvenliği | `flutter_secure_storage` web’de sınırlı → prod web stratejisi (Faz 3–5) |
| Flutter web prod | Service worker / önbellek stratejisi (isteğe bağlı iyileştirme) |
| Opsiyonel CI | GitHub Actions ile `docker build` smoke (`PHASES.md` [ ]) |

---

## Bu belgeyi güncellerken

1. Bir faz bittiğinde ilgili maddeleri `YAPILANLAR.md`’ye taşıyın (veya `PHASES.md` tablosunu güncelleyin).
2. `PHASES.md` tek doğruluk kaynağı olarak checkbox’ları güncel tutun.
3. Mimari değişikliklerde `SISTEM-MIMARISI.md` ve gerekiyorsa `ARCHITECTURE.md` senkronize edilsin.

---

*Vizyon diyagramı ve uzun vadeli bileşen listesi: `ARCHITECTURE.md`.*
