# fluent-logging — integration (details)

Reference overlay — `<project>/docker/fluent-logging.yml`. Working Python example —
`<project>/app/logging_setup.py` (overlay + Makefile + structured-logging setup).

## 1. Wiring the lib
- **PHP/composer:** `composer require xakki/fluent-log` → `vendor/xakki/fluent-log/`
  (contains `docker-fluent.yml` + `fluent-bit/` + `logrotate/`).
- **Non-composer (Python/Node):** git submodule, as a whole dir (needs the siblings
  `fluent-bit/`, `logrotate/`):
  ```bash
  git submodule add git@github.com:Xakki/fluent-log.git docker/vendor/fluent-log
  git -C docker/vendor/fluent-log checkout v0.1.2   # pin the release tag
  ```
  ⚠ Deploy must pull the submodule: `git submodule update --init docker/vendor/fluent-log`
  (the server needs SSH access to the private repo).

## 2. Overlay `docker/fluent-logging.yml`
YAML anchors are **file-local** → they do NOT cross `include`: declare `x-logging` again in the overlay.

```yaml
include:
    - docker/vendor/fluent-log/docker-fluent.yml      # composer: vendor/xakki/fluent-log/docker-fluent.yml

x-logging: &_logging
    logging:
        driver: fluentd
        options:
            fluentd-address: "${EXT_FLUENT_PORT}"
            fluentd-async: "true"
            fluentd-async-reconnect-interval: "1000ms"
            fluentd-buffer-limit: 8388608
            fluentd-write-timeout: "100s"
            tag: "service.{{.Name}}"
            labels: "com.docker.compose.service,com.docker.compose.project,com.docker.compose.image,tier,log_format"

services:
    app:
        <<: *_logging
        labels: { tier: "web" }          # log_format left unset → default = service name
        depends_on:
            fluent-bit: { condition: service_started }
    # … other services likewise; redis/mariadb/nginx/php → set log_format for their parser
```

- The `include` path resolves from the **project root**; bind mounts INSIDE `docker-fluent.yml`
  (`./fluent-bit`, `./logrotate`) — from the lib's own dir (that's why we vendor the whole dir).
- **Host dir for file-tail (`MYSQL_SLOWLOG_PATH`, `JSON_LOG_PATH`) — ABSOLUTE only.**
  The value lands in `volumes:` inside `docker-fluent.yml`, and Compose resolves a
  relative path from the LIB's dir, silently binding an empty/wrong dir instead of erroring. Don't put
  a relative value in `.env`; hand an absolute path from the Makefile (`$(CURDIR)/…`, exported).
- `log_format`: default = compose service name. For parsing, set it explicitly `php`/`nginx`/
  `mariadb`/`redis`. Anything else → `gl.auto`.

## 3. Env vars (`.env` + placeholders in `.env.example`)

| Var | Meaning | Example |
|---|---|---|
| `COMPOSE_PROJECT_NAME` | **required** — else `-fluent-bit` (leading dash) | `myproj` |
| `COMPOSE_FILE` | auto-merge overlay into all compose commands | `docker-compose.yml:docker/fluent-logging.yml` |
| `COMPOSE_PROFILES` | → `docker_profile` (tag in Graylog) | `prod` |
| `EXT_FLUENT_PORT` | host-side forward intake of fluent-bit (host:port) | `127.0.0.1:10101` |
| `EXT_FLUENT_METRIC_PORT` | fluent-bit metrics/health (:2020) | `127.0.0.1:10102` |
| `GRAYLOG_HOST` | GELF/HTTP host | `log.example.com` |
| `GRAYLOG_URI` | GELF endpoint | `/gelf` |
| `GRAYLOG_PORT` | GELF/HTTP port | `443` |
| `HOST_NAME` | logical name (GELF `hostname`) | `myhost-myproj` |
| `HOST_IP` | host IP (GELF `host` = Graylog `source`) | `203.0.113.10` |
| `TZ` | fluent-bit container timezone | `Europe/Moscow` |
| `JSON_LOG_PATH` | (opt.) host dir tailed into `/var/log/json` for NDJSON — **absolute** | `/srv/app/docker/logs` |
| `MYSQL_SLOWLOG_PATH` | (opt.) mariadb slowlog — **absolute** (Makefile `$(CURDIR)/…`) | `/srv/app/docker/logs` |

Ports: each project on the host gets its own `EXT_FLUENT_*` (don't collide; `ss -ltn`).
`HOST_IP`/`HOST_NAME` are handy to compute in the Makefile (`hostname -I`).

## 4. fluent-bit ports
| Internal | Purpose |
|---|---|
| 24224 | fluentd forward (TCP/UDP) — published as `EXT_FLUENT_PORT` |
| 2020 | HTTP health/metrics — published as `EXT_FLUENT_METRIC_PORT` |
| 2021 | Prometheus exporter (internal) |

## 5. Search in Graylog
`source` = host IP (shared by all projects on the host). Filter the project by
**`docker_project:<COMPOSE_PROJECT_NAME>`**, the service by `docker_service:<name>`.

## 6. Verification (order)
1. `docker compose config` — merge/anchor/bind paths OK (the oracle, do it first).
2. `docker compose up -d fluent-bit logrotate`; fluent-bit logs with no `[error]`.
3. Emit a log from a service → verify arrival in Graylog (`docker_project:<name>`) +
   fluent-bit output metrics (`fluentbit_output_proc_records_total` growing,
   `..._errors/retries` flat).

## 7. Routing (`log_format` → parsers)
The `log_format` label (default = service name) picks the parser set. Known:
`php`, `nginx`, `mariadb`, `redis`. Unknown format → `route_unknown` → `gl.auto`
(generic JSON + multiline join). `OUTPUT Match gl.*` catches everything → no logs lost.
