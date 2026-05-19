# server/

Flask + Flask-SocketIO sunucusu. Faz 1'de doldurulacak.

Beklenen iskelet:

```
server/
├── Dockerfile
├── docker-compose.yml
├── requirements.txt
├── .env.example
├── Makefile
├── app.py                  # Flask + SocketIO factory
├── api/
│   ├── __init__.py
│   ├── health.py
│   └── keys.py             # Faz 2
├── sockets/
│   ├── __init__.py
│   └── relay.py            # message:send / delivered
├── queue/
│   └── ephemeral.py        # in-memory + TTL
├── db/
│   ├── schema.sql
│   └── migrations/
└── tests/
    └── test_zero_leak.py
```

> Bu klasör Faz 1 başladığında doldurulacak. Detaylar için `../PHASES.md`.
