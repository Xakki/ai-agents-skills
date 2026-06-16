---
name: new-project-docker
description: При создании ЛЮБОГО нового проекта с нуля — сразу делать его в Docker (Dockerfile + docker-compose.yml) + Makefile + подключать логирование (skill fluent-logging) с первого дня. Use when scaffolding/bootstrapping a new project, repo, or service from scratch. Триггеры RU: «новый проект», «создай проект», «инициализируй проект/репозиторий», «с нуля», «заскаффоль», «подними сервис». EN: new project, scaffold, bootstrap a service, set up a repo from scratch, project skeleton.
---

# new-project-docker — новый проект = Docker + Makefile

**Инвариант: любой новый проект создаётся сразу контейнеризованным.** Не «сначала
локально, потом обернём» — с первого коммита есть `Dockerfile`, `docker-compose.yml`,
`Makefile` и проводка логов. Это убирает «у меня работает», даёт единые команды и
сразу включает наблюдаемость.

## Что создаём в скелете
1. **`Dockerfile`** — образ приложения (multi-stage если компилируемое; slim-база).
2. **`docker-compose.yml`** — сервис(ы) приложения + зависимости (БД/кеш/очередь).
   Каждому сервису — `restart`, `mem_limit`/`cpus`, healthcheck где уместно.
3. **`.env` + `.env.example`** — конфиг (секреты в `.env`, он в `.gitignore`;
   `.env.example` с плейсхолдерами в git).
4. **`Makefile`** — единые команды (шаблон в [templates.md](templates.md)):
   `help`, `info`, `up`, `down`, `ps`, `restart name=…`, `logs name=…`, `build`,
   `config`, `log-test`. `HOST_IP` вычисляется динамически (`hostname -I`).
5. **Логирование** — подключить **skill `fluent-logging`** сразу: submodule/composer
   либы, overlay `docker/fluent-logging.yml`, env-блок, `COMPOSE_FILE`. Контейнеры
   пишут структурный JSON в stdout → fluent-bit → Graylog.
6. **`.gitignore`**, `README.md`/`DEPLOY.md` со списком команд.

## Happy-path
1. Завести репо + `git init`.
2. `Dockerfile` + `docker-compose.yml` (приложение + зависимости).
3. `Makefile` из [templates.md](templates.md) — подогнать имена сервисов/портов.
4. `.env`/`.env.example` (вкл. блок fluent-logging из skill `fluent-logging`).
5. Подключить логи (skill `fluent-logging`): либа + overlay + `COMPOSE_FILE`.
6. `make config` → `make up` → `make log-test` → проверить приход в Graylog.

## Принципы
- **Порты хоста — уникальные** на машине (не коллизить с другими проектами; `ss -ltn`).
  Биндить на `127.0.0.1:<port>` если наружу не нужно.
- **`COMPOSE_PROJECT_NAME`** задавать в `.env` (иначе кривые имена контейнеров и
  префиксы в Graylog).
- **Лимиты ресурсов** (`mem_limit`/`cpus`) с запасом — но задавать, не оставлять без.
- **Зависимости — managed-образы** (postgres/redis/…), не ставить в образ приложения.
- **Деплой** = `docker compose build && up -d` (+ `git submodule update --init` если
  либа логов как submodule). Документировать в `DEPLOY.md`.

Шаблоны (`Makefile`, `docker-compose.yml`, `Dockerfile`) — в [templates.md](templates.md).
Проводку логов бери из skill `fluent-logging`.
