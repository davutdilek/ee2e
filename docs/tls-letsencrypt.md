# Production: TLS + Nginx Reverse Proxy + Let's Encrypt

> Faz 1'in sonunda devreye alınması önerilir. Ngrok dev için yeterli, prod için TLS terminasyonunu kontrol etmek istiyoruz.

## Hedef Mimari

```
İnternet ──443/tcp──> [Nginx (TLS terminator)] ──5000/tcp──> [ee2e-app] ──> [postgres]
                              │
                       Let's Encrypt
                       (HTTP-01 challenge / 80)
```

Sertifika auto-renew, WSS upgrade, HTTP→HTTPS redirect, modern cipher suite.

## Önkoşullar

- Domain (örn. `ee2e.example.com`) → A/AAAA record VPS IP'sine
- VPS port 80 ve 443 açık
- Docker + docker compose kurulu

## 1. `infra/nginx/nginx.conf`

```nginx
worker_processes auto;
events { worker_connections 1024; }

http {
    map $http_upgrade $connection_upgrade {
        default upgrade;
        ''      close;
    }

    server_tokens off;
    client_max_body_size 256k;       # E2EE mesajlar küçüktür

    # HTTP -> HTTPS + ACME challenge
    server {
        listen 80;
        server_name ee2e.example.com;

        location /.well-known/acme-challenge/ {
            root /var/www/certbot;
        }
        location / {
            return 301 https://$host$request_uri;
        }
    }

    server {
        listen 443 ssl;
        http2 on;
        server_name ee2e.example.com;

        ssl_certificate     /etc/letsencrypt/live/ee2e.example.com/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/ee2e.example.com/privkey.pem;

        # Modern profile (Mozilla SSL Config)
        ssl_protocols TLSv1.3 TLSv1.2;
        ssl_prefer_server_ciphers off;
        ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
        ssl_session_cache shared:SSL:10m;
        ssl_session_tickets off;

        add_header Strict-Transport-Security "max-age=63072000; includeSubDomains" always;
        add_header X-Content-Type-Options nosniff always;
        add_header Referrer-Policy no-referrer always;

        # Socket.IO + HTTP
        location / {
            proxy_pass http://app:5000;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection $connection_upgrade;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;

            proxy_read_timeout 3600s;     # uzun yaşayan WebSocket
            proxy_send_timeout 3600s;
            proxy_buffering off;
        }
    }
}
```

## 2. `infra/docker-compose.prod.yml`

```yaml
name: ee2e-prod

services:
  app:
    image: ee2e-app:latest      # CI'dan registry'ye push edilebilir
    restart: unless-stopped
    env_file: ../server/.env
    environment:
      DATABASE_URL: postgresql://ee2e:${POSTGRES_PASSWORD}@db:5432/ee2e
      CORS_ORIGINS: https://ee2e.example.com
    networks: [internal]
    depends_on:
      db: { condition: service_healthy }
    read_only: true
    tmpfs: [/tmp]
    cap_drop: [ALL]
    security_opt: ["no-new-privileges:true"]

  db:
    image: postgres:16-alpine
    restart: unless-stopped
    environment:
      POSTGRES_USER: ee2e
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ee2e
    networks: [internal]
    volumes:
      - postgres-data:/var/lib/postgresql/data
      - ../server/db/schema.sql:/docker-entrypoint-initdb.d/00-schema.sql:ro
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ee2e -d ee2e"]
      interval: 5s
      retries: 10

  nginx:
    image: nginx:1.27-alpine
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./certbot/conf:/etc/letsencrypt:ro
      - ./certbot/www:/var/www/certbot:ro
    networks: [internal, public]
    depends_on: [app]

  certbot:
    image: certbot/certbot:latest
    volumes:
      - ./certbot/conf:/etc/letsencrypt
      - ./certbot/www:/var/www/certbot
    entrypoint: >
      /bin/sh -c "trap exit TERM;
                  while :; do
                    certbot renew --webroot -w /var/www/certbot --quiet;
                    sleep 12h & wait $${!};
                  done"

networks:
  internal: { driver: bridge }
  public:   { driver: bridge }

volumes:
  postgres-data:
```

## 3. İlk Sertifika Alma

```bash
cd infra

# 1) Önce ACME challenge için sadece nginx ve certbot çalıştır (dummy cert ile)
mkdir -p certbot/conf certbot/www

# 2) Stage cert (rate-limit yememek için önce staging'i dene)
docker compose -f docker-compose.prod.yml run --rm certbot certonly \
  --webroot -w /var/www/certbot \
  --staging \
  --agree-tos --no-eff-email -m you@example.com \
  -d ee2e.example.com

# 3) İşe yaradıysa real cert
docker compose -f docker-compose.prod.yml run --rm certbot certonly \
  --webroot -w /var/www/certbot \
  --force-renewal \
  --agree-tos --no-eff-email -m you@example.com \
  -d ee2e.example.com

# 4) Tüm stack
docker compose -f docker-compose.prod.yml up -d
```

## 4. Doğrulama

```bash
curl -v https://ee2e.example.com/health
# → 200 + JSON

# WSS testi
npx wscat -c wss://ee2e.example.com/socket.io/?EIO=4&transport=websocket
```

[SSL Labs](https://www.ssllabs.com/ssltest/) → A+ skor hedefi.

## 5. Güvenlik Sertleştirme Notları

- Postgres portu **dışarı açılmaz** (sadece `internal` network'te)
- Nginx ve app container'ları arasındaki trafik `internal`, dışarıdan ulaşılamaz
- Container'lar `read_only` + `cap_drop: ALL` + `no-new-privileges`
- Cert'ler `certbot/conf/` içinde — buraya yazma izni sadece certbot container'ında
- Cloudflare önüne konulursa "Authenticated Origin Pulls" + WAF eklenmesi önerilir
- Rate-limiting (Nginx `limit_req` veya `flask-limiter`) DDoS azaltımı için şart

## 6. Backup Stratejisi (Faz 2 ile birlikte)

Faz 2'de `key_bundles` doldurulmaya başlayınca:
- Daily `pg_dump` → şifreli (gpg) → off-site (S3/B2)
- Postgres WAL archiving opsiyonel
- **Mesaj queue backup'lanmaz** — ephemeral olması zaten istenen davranış
