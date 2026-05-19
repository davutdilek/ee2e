# Ngrok Hızlı Başlangıç (Faz 1 — Dış Dünyaya Açılma)

Lokal sunucuyu arkadaşlarına test ettirebilmek için ngrok tüneli yeterli.

## 1. Sunucuyu çalıştır

```bash
cd server
make env       # .env oluşturur
$EDITOR .env   # POSTGRES_PASSWORD ve FLASK_SECRET'ı değiştir
make up
curl http://localhost:5000/health
# → {"status":"ok","db":true,"queued":0}
```

## 2. Ngrok'u kur ve aç

```bash
brew install ngrok            # macOS
# veya: https://ngrok.com/download

ngrok config add-authtoken <YOUR_TOKEN>
ngrok http 5000
```

Çıktıdan `Forwarding` satırındaki URL'i al (örn. `https://abcd-1234.ngrok-free.app`).

## 3. Test

```bash
curl https://abcd-1234.ngrok-free.app/health
```

Telefonundaki/arkadaşının cihazındaki Flutter app'e bu URL'i `wss://abcd-1234.ngrok-free.app` olarak gir.

## 4. Production'a Geçiş (Faz 1 sonu)

Ngrok dev için ideal; production için:

- Küçük VPS (Hetzner/DigitalOcean, $5/ay yeterli)
- Domain + Cloudflare DNS
- Nginx reverse proxy + Let's Encrypt (`certbot --nginx`)
- `wss://ee2e.example.com`

Detaylı setup `docs/tls-letsencrypt.md`'de (Faz 1 sonunda yazılacak).
