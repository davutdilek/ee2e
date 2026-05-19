.PHONY: help up down logs ps shell psql rebuild test test-no-leak env

COMPOSE ?= docker compose

help:
	@echo "make up            - build & start (db + app)"
	@echo "make down          - stop & remove containers"
	@echo "make logs          - tail app logs"
	@echo "make ps            - container status"
	@echo "make shell         - shell into app"
	@echo "make psql          - psql into db"
	@echo "make rebuild       - no-cache build + up"
	@echo "make test          - run pytest in container"
	@echo "make test-no-leak  - verify no plaintext leaks to logs"
	@echo "make env           - copy .env.example -> .env (if missing)"

env:
	@test -f .env || (cp .env.example .env && echo "Created .env from .env.example — EDIT IT.")

up: env
	$(COMPOSE) up -d --build
	@echo "→ http://localhost:5000/health"

down:
	$(COMPOSE) down

logs:
	$(COMPOSE) logs -f app

ps:
	$(COMPOSE) ps

shell:
	$(COMPOSE) exec app sh

psql:
	$(COMPOSE) exec db psql -U ee2e -d ee2e

rebuild:
	$(COMPOSE) build --no-cache
	$(COMPOSE) up -d

test:
	$(COMPOSE) exec app python -m pytest -q

test-no-leak:
	@echo "Sending canary message and verifying it does NOT appear in logs..."
	@$(COMPOSE) logs --no-color app | grep -F "EE2E_CANARY_PLAINTEXT" \
	  && (echo "❌ LEAK DETECTED" && exit 1) \
	  || echo "✅ no plaintext leak"
