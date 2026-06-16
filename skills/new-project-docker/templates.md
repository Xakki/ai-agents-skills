# Шаблоны скелета (Docker + Makefile)

Подогнать имена сервисов, порты, базовый образ. Логирование — отдельно из skill
`fluent-logging` (overlay `docker/fluent-logging.yml` + env).

## Makefile (обобщённый)
```makefile
SHELL = /bin/bash
include .env
-include .env.local
export

TTY ?= $(shell if [ -t 0 ]; then echo "-it"; else echo "-T"; fi)
PWD := $(shell pwd)
HOST_NAME := $(shell hostname)
# IP хоста — source в GELF-логах (перекрывает .env при запуске через make).
HOST_IP := $(shell hostname -I 2>/dev/null | awk '{print $$1}' || echo unknown)
export HOST_IP
dc := docker compose

##@ Help
help:  ## Показать справку
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z0-9_@-]+:.*?##/ { printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0,5) }' $(MAKEFILE_LIST)

info: ## Инфо о проекте/логировании
	@echo "⚡ PROJECT: $(COMPOSE_PROJECT_NAME)  Graylog: $(GRAYLOG_HOST) source=$(HOST_NAME)/$(HOST_IP)"

##@ Dockers
config: ## Валидировать смёрженный compose
	$(dc) config -q && echo "compose config OK"
build: ## Пересобрать образ(ы)
	$(dc) build
up: ## up -d (весь стек)
	$(dc) up -d && $(MAKE) info --no-print-directory
up-fluent: ## Поднять только логи (fluent-bit + logrotate)
	$(dc) up -d fluent-bit logrotate
down: ## down
	$(dc) down
ps: ## ps
	$(dc) ps
restart: ## Пересоздать сервис(ы) (optional `name`)
	$(dc) up -d --force-recreate --remove-orphans --no-deps $(name)
logs: ## Логи последние 200 (optional `name`)
	$(dc) logs --tail=200 $(name)
logs-follow: ## Логи follow (optional `name`)
	$(dc) logs --tail=20 --follow $(name)

##@ Fluent / Graylog
fluent-errors: ## Ошибки fluent-bit
	$(dc) logs --tail=500 fluent-bit | grep -iE "\[error\]|\[warn\]|fail|drop|refused" || echo "fluent-bit OK"
fluent-metrics: ## Метрики fluent-bit
	@P=$$(echo "$(EXT_FLUENT_METRIC_PORT)" | sed -E 's/.*:([0-9]+)$$/\1/'); \
	curl -s "http://127.0.0.1:$$P/api/v1/metrics/prometheus" | grep -E "fluentbit_output_(proc_records|errors|retries)_total"
```
Добавляй проектные таргеты: `migrate`, `psql`/`db-shell`, `test`, `log-test`
(дёрнуть HTTP-эндпоинт → access-лог → Graylog).

## docker-compose.yml (скелет)
```yaml
services:
  app:
    build: .
    command: <запуск>          # uvicorn / php-fpm / node …
    ports:
      - "127.0.0.1:<host>:<cont>"   # только loopback, если наружу не нужно
    env_file: .env
    depends_on: [postgres, redis]
    restart: always
    mem_limit: "512M"
    cpus: "1.0"

  postgres:
    image: postgres:16        # или pgvector/pgvector:pg16
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
Логи — НЕ дублировать здесь: overlay `docker/fluent-logging.yml` навешивает
`<<: *_logging` на сервисы и активируется через `COMPOSE_FILE` в `.env`
(skill `fluent-logging`).

## Dockerfile (пример Python)
```dockerfile
FROM python:3.12-slim
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends build-essential curl \
    && rm -rf /var/lib/apt/lists/*
COPY . .
RUN pip install --no-cache-dir -e .
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

## .env (минимум + блок логов)
```
COMPOSE_PROJECT_NAME=<имя>
COMPOSE_FILE=docker-compose.yml:docker/fluent-logging.yml
# … секреты приложения …
# Блок fluent-logging (env-таблица — в skill fluent-logging / integration.md):
EXT_FLUENT_PORT=127.0.0.1:<свободный>
EXT_FLUENT_METRIC_PORT=127.0.0.1:<свободный+1>
GRAYLOG_HOST=...
GRAYLOG_URI=/gelf
GRAYLOG_PORT=443
HOST_NAME=<host>-<проект>
HOST_IP=127.0.0.1
TZ=Europe/Moscow
COMPOSE_PROFILES=prod
```
