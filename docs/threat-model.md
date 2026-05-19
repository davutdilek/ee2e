# Tehdit Modeli — STRIDE

> Faz 1 odaklı; her faz başında genişletilir.

## Aktörler

- **Kullanıcı** (Ali, Ayşe) — meşru istemci
- **Pasif Dinleyici** — ağ trafiğini görür, müdahale edemez (ISP, kahve dükkânı WiFi)
- **Aktif Saldırgan** — paket enjekte edebilir (MitM)
- **Sunucu Operatörü** — bizim de güvenmediğimiz aktör (kendimiz dahil!)
- **Cihaz Hırsızı** — fiziksel cihaza erişen

## STRIDE Matrisi

| Tehdit                   | Senaryo                                          | Karşı Önlem (Faz 1)                       | Faz 3+'te Güçlenecek    |
|--------------------------|--------------------------------------------------|-------------------------------------------|--------------------------|
| **S**poofing             | Saldırgan, Ayşe gibi davranıp Ali'ye mesaj atar  | JWT/client-token (zayıf, geçici)          | IK signature doğrulama   |
| **T**ampering            | MitM payload'ı değiştirir                        | TLS 1.3 (wss://)                          | AEAD (AES-GCM) tag       |
| **R**epudiation          | Ali "ben atmadım" der                            | (kapsam dışı — özellik değil!)            | Deniability özelliği     |
| **I**nformation Disclosure | Sunucu ele geçer, mesajlar okunur               | Loglara yazma, ephemeral queue            | Zero-Knowledge (E2EE)    |
| **D**oS                  | `connect` flood ile sunucu çöker                | Rate-limit (`flask-limiter`)              | Cloudflare WAF           |
| **E**levation of Privilege | Container'dan host'a kaçış                     | non-root, cap_drop, read_only             | Rootless Docker / gVisor |

## Kapsam Dışı (Bilinçli Olarak)

- Endpoint compromise (cihaza malware bulaşırsa, oyun biter — bizim çözebileceğimiz bir şey değil)
- Trafik analizi (kim kime, ne zaman, ne kadar yazıyor) — **Faz 4 Sealed Sender + Padding** ile kısmen
- Quantum saldırgan — post-quantum kripto Faz 5'in ötesi
