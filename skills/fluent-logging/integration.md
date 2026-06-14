# fluent-logging — интеграция (детали)

Эталон overlay — `<project>/docker/fluent-logging.yml`. Рабочий Python-пример —
`<project>/app/logging_setup.py` (overlay + Makefile + structured-logging setup).

## 1. Подключение либы
- **PHP/composer:** `composer require xakki/fluent-log` → `vendor/xakki/fluent-log/`
  (содержит `docker-fluent.yml` + `fluent-bit/` + `logrotate/`).
- **Не-composer (Python/Node):** git submodule, целым каталогом (нужны соседи
  `fluent-bit/`, `logrotate/`):
  ```bash
  git submodule add git@github.com:Xakki/fluent-log.git docker/vendor/fluent-log
  git -C docker/vendor/fluent-log checkout v0.1.2   # пинить релиз-тег
  ```
  ⚠ Деплой обязан тянуть submodule: `git submodule update --init docker/vendor/fluent-log`
  (нужен SSH-доступ сервера к приватному репо).

## 2. Overlay `docker/fluent-logging.yml`
Якоря YAML **file-local** → НЕ пересекают `include`: объяви `x-logging` заново в overlay.

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
        labels: { tier: "web" }          # log_format не задаём → дефолт = имя сервиса
        depends_on:
            fluent-bit: { condition: service_started }
    # … остальные сервисы аналогично; redis/mariadb/nginx/php → задать log_format под их парсер
```

- `include`-путь резолвится от **корня проекта**; bind-маунты ВНУТРИ `docker-fluent.yml`
  (`./fluent-bit`, `./logrotate`) — от каталога самой либы (потому вендорим каталогом).
- `log_format`: дефолт = имя compose-сервиса. Для парсинга задавай явно `php`/`nginx`/
  `mariadb`/`redis`. Прочее → `gl.auto`.

## 3. Env-переменные (`.env` + плейсхолдеры в `.env.example`)

| Переменная | Смысл | Пример |
|---|---|---|
| `COMPOSE_PROJECT_NAME` | **обязательно** — иначе `-fluent-bit` (ведущий дефис) | `myproj` |
| `COMPOSE_FILE` | авто-мёрж overlay во все команды compose | `docker-compose.yml:docker/fluent-logging.yml` |
| `COMPOSE_PROFILES` | → `docker_profile` (тег в Graylog) | `prod` |
| `EXT_FLUENT_PORT` | хостовой forward-приём fluent-bit (host:port) | `127.0.0.1:10101` |
| `EXT_FLUENT_METRIC_PORT` | метрики/health fluent-bit (:2020) | `127.0.0.1:10102` |
| `GRAYLOG_HOST` | GELF/HTTP хост | `log.example.com` |
| `GRAYLOG_URI` | GELF endpoint | `/gelf` |
| `GRAYLOG_PORT` | GELF/HTTP порт | `443` |
| `HOST_NAME` | логическое имя (GELF `hostname`) | `myhost-myproj` |
| `HOST_IP` | IP хоста (GELF `host` = Graylog `source`) | `203.0.113.10` |
| `TZ` | таймзона контейнера fluent-bit | `Europe/Moscow` |
| `JSON_LOG_PATH` | (опц.) хост-дир тейлится в `/var/log/json` для NDJSON | `/var/log/` |
| `MYSQL_SLOWLOG_PATH` | (опц.) slowlog mariadb | `/var/log/` |

Порты: каждый проект на хосте — свои `EXT_FLUENT_*` (не коллизить; `ss -ltn`).
`HOST_IP`/`HOST_NAME` удобно вычислять в Makefile (`hostname -I`).

## 4. Порты fluent-bit
| Внутр. | Назначение |
|---|---|
| 24224 | fluentd forward (TCP/UDP) — публикуется как `EXT_FLUENT_PORT` |
| 2020 | HTTP health/metrics — публикуется как `EXT_FLUENT_METRIC_PORT` |
| 2021 | Prometheus exporter (внутренний) |

## 5. Поиск в Graylog
`source` = IP хоста (общий для всех проектов на хосте). Фильтруй проект по
**`docker_project:<COMPOSE_PROJECT_NAME>`**, сервис — `docker_service:<имя>`.

## 6. Верификация (порядок)
1. `docker compose config` — мёрж/якорь/bind-пути ОК (оракул, делать первым).
2. `docker compose up -d fluent-bit logrotate`; логи fluent-bit без `[error]`.
3. Эмитнуть лог сервисом → проверить приход в Graylog (`docker_project:<имя>`) +
   output-метрики fluent-bit (`fluentbit_output_proc_records_total` растёт,
   `..._errors/retries` плоские).
