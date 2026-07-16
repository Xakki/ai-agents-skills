---
name: fluent-logging
description: Cross-project logging standard. ALL projects log via xakki/fluent-log (fluent-bit → Graylog GELF); containers write STRUCTURED logs (JSON) to stdout/stderr. Use when setting up or changing logging in any project, dockerizing logs, wiring fluent-bit/Graylog, or the question of how/where to log, which level/format, secret redaction comes up. Laravel → composer require xakki/laralog; Python → JSON-to-stdout. Триггеры RU: «настрой логи», «логирование», «куда писать логи», «fluent-bit», «graylog», «структурные логи». EN: logging setup, structured logs, fluent-bit, graylog, log level/format.
---

# fluent-logging — unified logging standard

**Invariant: every project ships logs to Graylog via `xakki/fluent-log`.**
Containers write **structured JSON** to stdout/stderr (or an NDJSON file) →
Docker fluentd driver → `fluent-bit` (GELF) → Graylog. fluent-bit metrics → Prometheus.

- Lib: <https://github.com/Xakki/FluentLog> (`xakki/fluent-log`).
- Log rules themselves (levels / fields / what not to log) — [rules.md](rules.md)
  (digest of LaraLog `docs/LoggingRules.ru.md`, language-agnostic).

## Happy-path (any stack)
1. **Lib.** PHP/composer: `composer require xakki/fluent-log`. Otherwise — git submodule
   `docker/vendor/fluent-log` (as a whole dir).
2. **Overlay `docker/fluent-logging.yml`:** `include:` the lib's `docker-fluent.yml` +
   COPY the `x-logging` anchor (anchors don't cross `include`) + `<<: *_logging` +
   `labels:{tier,log_format}` + `depends_on: fluent-bit` on your services.
3. **`.env`:** activate via `COMPOSE_FILE`; set `COMPOSE_PROJECT_NAME`
   (required — otherwise a name with a leading dash!), `EXT_FLUENT_*`, `GRAYLOG_*`,
   `HOST_NAME/IP`, `TZ`.
4. **Makefile:** `HOST_IP` from `hostname -I`, `log-test` target (see `new-project-docker`).
5. **Verify end-to-end** → find in Graylog by `docker_project:<name>` (`source` =
   host IP, shared; distinguish by `docker_project`/`docker_service`).

Steps 2–5 in full (overlay snippet, env table, fluent-bit ports, search, verification
order, `log_format`→parsers routing) — [integration.md](integration.md).

## Per-stack
- **Laravel:** `composer require xakki/laralog` (structured Monolog) + `log_format:"php"`.
- **Python:** one JSON line per record to stdout (`json_default` fluent-bit unpacks it;
  `log_format` can be left unset → `gl.auto`). Formatter + redaction filter —
  [python.md](python.md). Reference: `<project>/app/logging_setup.py`.
- **Node/other:** same principle — structured JSON to stdout, secrets redacted.

## CRITICAL safety
- **NEVER log secrets/PII** (tokens, passwords, keys, sessions, full
  request/response body, email in plaintext). Redact **before** emit (ban-list
  filter). Common leak — httpx/SDK log a URL with the token in the path.
- **Logging never fails the request** — best-effort (`fluentd-async: true`): Graylog/socket
  unavailable → request completes normally.
- **Log once, at the boundary**; values go in `context` fields (snake_case,
  typed), NOT interpolated into `message`.
- **Host paths for file-tail (`MYSQL_SLOWLOG_PATH`/`JSON_LOG_PATH`) — ABSOLUTE only**
  (a relative one silently binds an empty/wrong dir; details — [integration.md](integration.md)).
- `COMPOSE_FILE` in `.env` changes ALL `docker compose` commands (auto-merges the overlay).
- Switching a service to the fluentd driver = container recreation (DB — during a
  maintenance window; the app pool must survive, Python `pool_pre_ping=True`).

Details on demand: [integration.md](integration.md), [rules.md](rules.md), [python.md](python.md).
