---
name: new-project-docker
description: >
  Scaffold a new project, repository, or service in Docker from day one with
  a Dockerfile, Docker Compose, Makefile, and fluent logging. Use for a new
  project, bootstrap, service setup, or project skeleton.
---

# new-project-docker — new project = Docker + Makefile

**Invariant: every new project is containerized from the start.** Not "local first,
wrap it later" — from the first commit there's a `Dockerfile`, `docker-compose.yml`,
`Makefile` and log wiring. This kills "works on my machine", gives unified commands and
turns on observability right away.

## What we create in the skeleton
1. **`Dockerfile`** — app image (multi-stage if compiled; slim base).
2. **`docker-compose.yml`** — app service(s) + deps (db/cache/queue).
   Each service — `restart`, `mem_limit`/`cpus`, healthcheck where apt.
3. **`.env` + `.env.example`** — cfg (secrets in `.env`, it's in `.gitignore`;
   `.env.example` with placeholders in git).
4. **`Makefile`** — unified commands (template in [templates.md](templates.md)):
   `help`, `info`, `up`, `down`, `ps`, `restart name=…`, `logs name=…`, `build`,
   `config`, `log-test`. `HOST_IP` computed dynamically (`hostname -I`).
5. **Logging** — wire up **skill `fluent-logging`** right away: submodule/composer
   libs, overlay `docker/fluent-logging.yml`, env block, `COMPOSE_FILE`. Containers
   write structured JSON to stdout → fluent-bit → Graylog.
6. **`.gitignore`**, `README.md`/`DEPLOY.md` with the command list.

## Happy-path
1. Create repo + `git init`. Commits — per [git-flow](../git-flow/SKILL.md) core.
2. `Dockerfile` + `docker-compose.yml` (app + deps).
3. `Makefile` from [templates.md](templates.md) — adjust service names/ports.
4. `.env`/`.env.example` (incl. fluent-logging block from skill `fluent-logging`).
5. Wire up logs (skill `fluent-logging`): lib + overlay + `COMPOSE_FILE`.
6. `make config` → `make up` → `make log-test` → check arrival in Graylog.

## Principles
- **Host ports — unique** on the machine (don't collide with other projects; `ss -ltn`).
  Bind to `127.0.0.1:<port>` if not needed externally.
- **`COMPOSE_PROJECT_NAME`** set in `.env` (else broken container names and
  prefixes in Graylog).
- **Resource limits** (`mem_limit`/`cpus`) with headroom — but set them, don't leave unset.
- **Deps — managed images** (postgres/redis/…), don't install into the app image.
- **Deploy** = `docker compose build && up -d` (+ `git submodule update --init` if
  log lib is a submodule). Document in `DEPLOY.md`.

Templates (`Makefile`, `docker-compose.yml`, `Dockerfile`) — in [templates.md](templates.md).
Take log wiring from skill `fluent-logging`.
