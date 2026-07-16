# Skeleton templates (Docker + Makefile)

Adjust service names, ports, base image. Logging — separately from skill
`fluent-logging` (overlay `docker/fluent-logging.yml` + env).

## Makefile (generic)
```makefile
SHELL = /bin/bash
include .env
-include .env.local
export

TTY ?= $(shell if [ -t 0 ]; then echo "-it"; else echo "-T"; fi)
PWD := $(shell pwd)
HOST_NAME := $(shell hostname)
# Host IP — source in GELF logs (overrides .env when run via make).
HOST_IP := $(shell hostname -I 2>/dev/null | awk '{print $$1}' || echo unknown)
export HOST_IP
dc := docker compose

##@ Help
help:  ## Show help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z0-9_@-]+:.*?##/ { printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0,5) }' $(MAKEFILE_LIST)

info: ## Info about project/logging
	@echo "⚡ PROJECT: $(COMPOSE_PROJECT_NAME)  Graylog: $(GRAYLOG_HOST) source=$(HOST_NAME)/$(HOST_IP)"

##@ Dockers
config: ## Validate merged compose
	$(dc) config -q && echo "compose config OK"
build: ## Rebuild image(s)
	$(dc) build
up: ## up -d (whole stack)
	$(dc) up -d && $(MAKE) info --no-print-directory
up-fluent: ## Bring up logs only (fluent-bit + logrotate)
	$(dc) up -d fluent-bit logrotate
down: ## down
	$(dc) down
ps: ## ps
	$(dc) ps
restart: ## Recreate service(s) (optional `name`)
	$(dc) up -d --force-recreate --remove-orphans --no-deps $(name)
logs: ## Last 200 log lines (optional `name`)
	$(dc) logs --tail=200 $(name)
logs-follow: ## Follow logs (optional `name`)
	$(dc) logs --tail=20 --follow $(name)

##@ Fluent / Graylog
fluent-errors: ## fluent-bit errors
	$(dc) logs --tail=500 fluent-bit | grep -iE "\[error\]|\[warn\]|fail|drop|refused" || echo "fluent-bit OK"
fluent-metrics: ## fluent-bit metrics
	@P=$$(echo "$(EXT_FLUENT_METRIC_PORT)" | sed -E 's/.*:([0-9]+)$$/\1/'); \
	curl -s "http://127.0.0.1:$$P/api/v1/metrics/prometheus" | grep -E "fluentbit_output_(proc_records|errors|retries)_total"
```
Add project targets: `migrate`, `psql`/`db-shell`, `test`, `log-test`
(hit an HTTP endpoint → access log → Graylog).

## docker-compose.yml (skeleton)
```yaml
services:
  app:
    build: .
    command: <start>          # uvicorn / php-fpm / node …
    ports:
      - "127.0.0.1:<host>:<cont>"   # loopback only, if not exposed externally
    env_file: .env
    depends_on: [postgres, redis]
    restart: always
    mem_limit: "512M"
    cpus: "1.0"

  postgres:
    image: postgres:16        # or pgvector/pgvector:pg16
    environment:
      POSTGRES_DB: ${DB_NAME}
      POSTGRES_USER: ${DB_USER}
      POSTGRES_PASSWORD: ${DB_PASSWORD}
    volumes: [pg_data:/var/lib/postgresql/data]
    restart: always
    mem_limit: "1G"

  redis:
    image: redis:7-alpine
    volumes: [redis_data:/data]
    restart: always
    mem_limit: "256M"

volumes:
  pg_data:
  redis_data:
```
Logs — do NOT duplicate here: overlay `docker/fluent-logging.yml` attaches
`<<: *_logging` to services and is activated via `COMPOSE_FILE` in `.env`
(skill `fluent-logging`).

## Dockerfile (Python example)
```dockerfile
FROM python:3.12-slim
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends build-essential curl \
    && rm -rf /var/lib/apt/lists/*
COPY . .
RUN pip install --no-cache-dir -e .
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

## .env (minimum + logs block)
```
COMPOSE_PROJECT_NAME=<name>
COMPOSE_FILE=docker-compose.yml:docker/fluent-logging.yml
# … app secrets …
# fluent-logging block (env table — in skill fluent-logging / integration.md):
EXT_FLUENT_PORT=127.0.0.1:<free>
EXT_FLUENT_METRIC_PORT=127.0.0.1:<free+1>
GRAYLOG_HOST=...
GRAYLOG_URI=/gelf
GRAYLOG_PORT=443
HOST_NAME=<host>-<project>
HOST_IP=127.0.0.1
TZ=Europe/Moscow
COMPOSE_PROFILES=prod
```
