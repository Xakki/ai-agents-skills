---
name: fluent-logging
description: Cross-project logging standard. ВСЕ проекты логируют через xakki/fluent-log (fluent-bit → Graylog GELF); контейнеры пишут СТРУКТУРИРОВАННЫЕ логи (JSON) в stdout/stderr. Use when setting up or changing logging in any project, dockerizing logs, wiring fluent-bit/Graylog, или встаёт вопрос «как/куда логировать», какой уровень/формат, маскировка секретов. Laravel → composer require xakki/laralog; Python → JSON-в-stdout. Триггеры RU: «настрой логи», «логирование», «куда писать логи», «fluent-bit», «graylog», «структурные логи». EN: logging setup, structured logs, fluent-bit, graylog, log level/format.
---

# fluent-logging — единый стандарт логирования

**Инвариант: каждый проект шлёт логи в Graylog через `xakki/fluent-log`.**
Контейнеры пишут **структурированный JSON** в stdout/stderr (или NDJSON-файл) →
Docker fluentd-драйвер → `fluent-bit` нормализует в GELF → Graylog. Метрики
fluent-bit → Prometheus.

- Либа: <https://github.com/Xakki/FluentLog> (composer-пакет `xakki/fluent-log`).
- Правила САМИХ логов (уровни/поля/что не логировать): база — LaraLog
  `docs/LoggingRules.ru.md`, конспект в [rules.md](rules.md). Принципы языко-независимы.

## Happy-path интеграции (любой стек)
1. **Подключить либу.**
   - PHP/composer-проект: `composer require xakki/fluent-log` → лежит в `vendor/xakki/fluent-log/`.
   - Иначе (Python/Node/…): git submodule `docker/vendor/fluent-log` →
     `git submodule add git@github.com:Xakki/fluent-log.git docker/vendor/fluent-log`.
2. **Overlay `docker/fluent-logging.yml`** (сторона проекта): `include:` либиного
   `docker-fluent.yml` + СКОПИРОВАТЬ якорь `x-logging` (анкоры не пересекают `include`)
   + навесить `<<: *_logging` + `labels: {tier, log_format}` + `depends_on: fluent-bit`
   на свои сервисы. Детали и сниппет — [integration.md](integration.md).
3. **`.env`**: активировать через `COMPOSE_FILE` + задать env-переменные (полная
   таблица в [integration.md](integration.md)): `COMPOSE_PROJECT_NAME` (обязательно!),
   `COMPOSE_FILE`, `EXT_FLUENT_PORT`, `EXT_FLUENT_METRIC_PORT`, `GRAYLOG_HOST/URI/PORT`,
   `HOST_NAME`, `HOST_IP`, `TZ`, `COMPOSE_PROFILES`.
4. **Makefile**: `HOST_IP` динамически из `hostname -I`, таргет `log-test`. См. скил
   `new-project-docker`.
5. **Проверить end-to-end**: `docker compose config` → `up -d fluent-bit logrotate` →
   эмитнуть тест-лог → найти в Graylog по `docker_project:<имя>` (поле `source` в
   Graylog = IP хоста, общий; различай по `docker_project`/`docker_service`).

## Маршрутизация (важно)
`log_format` (лейбл, дефолт = имя сервиса) выбирает набор парсеров. Известные:
`php`, `nginx`, `mariadb`, `redis`. Неизвестный формат → `route_unknown` → `gl.auto`
(generic JSON + склейка многострочки). `OUTPUT Match gl.*` ловит всё → логи не теряются.

## Per-stack
- **Laravel:** `composer require xakki/laralog` (структурный Monolog, формат под эту
  либу) + `log_format: "php"`. См. <https://github.com/Xakki/LaraLog>.
- **Python:** писать **одну JSON-строку на запись в stdout** (глобальный `json_default`
  fluent-bit её развернёт; `log_format` можно не задавать → `gl.auto`). Конкретные
  правила, formatter и фильтр-маскировка — [python.md](python.md). Готовый пример:
  `<project>/app/logging_setup.py`.
- **Node/прочее:** тот же принцип — структурный JSON в stdout, секреты замаскированы.

## CRITICAL safety
- **НИКОГДА не логировать секреты/PII** (токены, пароли, ключи, сессии, полные
  request/response body, email в открытом виде). Маскировать **до** эмита (фильтр с
  ban-list). Частый источник утечки — httpx/SDK логируют URL с токеном в пути.
- **Логирование не должно ронять запрос** — best-effort: Graylog/сокет недоступен →
  запрос завершается штатно (`fluentd-async: true`).
- **Логируй один раз, на границе** — не catch-log-rethrow на каждом уровне.
- Значения — в `context`-полях (snake_case, типизированные), НЕ интерполяцией в `message`.
- `COMPOSE_FILE` в `.env` меняет ВСЕ команды `docker compose` (авто-мёрж overlay).
- Перевод существующего сервиса на fluentd-драйвер = рекреация контейнера. Для БД
  (postgres/mysql) это бонс → делать в окне; пул приложения должен переживать (Python:
  `pool_pre_ping=True`).

Детали по запросу подгружай из соседних файлов: [integration.md](integration.md),
[rules.md](rules.md), [python.md](python.md).
