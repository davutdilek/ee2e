# Terimler Sözlüğü

| Terim | Açılım / Tanım |
|-------|----------------|
| **E2EE** | End-to-End Encryption — Sadece gönderici ve alıcı çözebilir; aradaki hiçbir aktör (sunucu dahil) okuyamaz. |
| **IK** | Identity Key — Kullanıcının uzun ömürlü kimlik anahtarı (Ed25519). Asla değişmez. |
| **SPK** | Signed PreKey — IK ile imzalanmış, periyodik (haftalık/aylık) yenilenen X25519 anahtarı. |
| **OPK** | One-Time PreKey — Tek kullanımlık X25519 anahtarı. Kullanılır kullanılmaz silinir. |
| **X3DH** | Extended Triple Diffie-Hellman — İlk shared secret türetme protokolü (Signal). |
| **Double Ratchet** | Her mesajda yeni anahtar türeten, forward & backward secrecy sağlayan algoritma. |
| **Sender Keys** | WhatsApp grup şifreleme modeli — her gönderici grup için ayrı symmetric chain. |
| **MLS** | Messaging Layer Security (RFC 9420) — Ölçeklenebilir grup E2EE standardı (TreeKEM tabanlı). |
| **TreeKEM** | MLS'in altında yatan ağaç-yapılı anahtar paylaşım protokolü. |
| **AEAD** | Authenticated Encryption with Associated Data — Hem şifreleme hem bütünlük (örn. AES-GCM, ChaCha20-Poly1305). |
| **Forward Secrecy** | Bugünkü anahtar çalınsa bile dünkü mesajların açılamaması. |
| **Post-Compromise Security** | Tam tersi — bugünkü anahtar çalındıktan sonra yeni mesajların güvende olması (Ratchet sağlar). |
| **Sealed Sender** | Mesajın gönderici kimliğinin de şifrelenmesi (metadata koruması). |
| **Padding** | Mesaj boyutunu sabitleyerek trafik analizini zorlaştırma. |
| **Zero-Knowledge** | Sunucunun, kullanıcı verisi hakkında "hiçbir şey bilmediği" mimari prensip. |
| **Ephemeral Storage** | Veriyi mümkün olan en kısa süre, mümkünse sadece RAM'de tutmak. |
| **Key Bundle** | Bir kullanıcının publish ettiği public anahtar paketi: `{IK_pub, SPK_pub, SPK_sig, [OPK_pub]}`. |
| **Room** | Socket.IO terimi — bir kanala katılmış socket'lerin grubu; mesaj routing için kullanılır. |
| **WSS** | WebSocket Secure — TLS üzerinden WebSocket (`wss://`). |
