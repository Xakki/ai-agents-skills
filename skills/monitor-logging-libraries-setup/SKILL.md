---
name: monitor-logging-libraries-setup
description: 'Set up or review application and nginx logging with the owner''s Xakki logging libraries (log-fluent collector, log-laravel, log-symfony, log-python, legacy phperrorcatcher) and enforce the LoggingRules. Use whenever adding, changing or reviewing logging in a project. RU: логирование в проекте, библиотеки логирования, настроить логи php python nginx, правила логирования.'
license: MIT
---

# Logging with the Xakki libraries

One pipeline for every project: the app writes structured JSON to stdout/stderr, the `log-fluent` collector (Fluent Bit) normalizes it and ships it to the central log store. Do not invent per-project loggers, syslog targets or per-project nginx log formats.

## Mandatory rules: LoggingRules

Before writing or reviewing any log call, read the rules and follow them; they are the cross-language contract, and the libraries only implement them:

- <https://github.com/Xakki/log-laravel/blob/main/docs/LoggingRules.md> (Russian: `LoggingRules.ru.md`, same folder)
- field names and types: `ContextFieldNaming.md` in the same `docs/` folder (the last `_` segment of a context key declares its type; never rename a field, never emit one field with two JSON types)

Prefer fetching the current file over relying on memory. A local checkout, if present, is `~/libs/log-laravel/docs/`. If neither is reachable, say so; do not reconstruct the rules from this digest alone.

Digest of what reviews must check (the rules file is authoritative):

- **Never log** passwords, tokens, API keys, session ids, full payment data, government ids, medical data, bulk PII, raw bodies of endpoints that carry them. Redact at the source; watch HTTP dumps, traces with arguments, ORM bindings and exception messages with user input.
- **Structure over prose.** `message` is a short constant sentence without interpolated values; everything searchable goes into a flat `context` array (`order_id`, `user_id`, `tag`). Business identifiers are ints, non-integer ids (uuid, hash) must be pinned to string.
- **Log once, at the boundary.** No catch-log-rethrow at every level; rethrow with `previous`. Logging must never fail the request.
- **Levels** follow the decision tree: warning only with a concrete action (otherwise notice); warning = failure absorbed, error = failure escaped; retries: first failure notice, later attempts warning, exhaustion error. Production default is `info`; debug is never global.
- **Cardinality:** per-request values (`request_id`, `user_id`, full URLs) are fields, never index labels; `tag` comes from a whitelist.
- Audit events are a separate durable channel, not the operational logger.

## Choose the library by stack

| Stack | Library | Install |
|---|---|---|
| Collector (every Docker host) | <https://github.com/Xakki/log-fluent> | Composer `xakki/log-fluent`, or git submodule pinned to a tag for non-PHP stacks. The old `xakki/fluent-log` is dead |
| Laravel | <https://github.com/Xakki/log-laravel> | `composer require xakki/laralog` |
| Symfony | <https://github.com/Xakki/log-symfony> | `composer require xakki/log-symfony` (not a bundle: wire a Monolog processor, or the PSR-3 `EnrichingLogger` decorator) |
| Python | <https://github.com/Xakki/log-python> | dist `xakki-pylog`, import `pylog`, call `pylog.setup()` once |
| PHP without Symfony and Laravel (incl. 5.6) | `xakki/phperrorcatcher` | **Legacy.** Only for such projects; never add it to a Laravel or Symfony project |

Read the chosen repository's README for the current wiring before editing; versions and options change.

## Workflow

1. Detect the stack and any existing logging; keep the project's field and severity contract unless the task changes it. Do not mix two loggers in one process.
2. Wire the library per its README. Log to stdout/stderr (or NDJSON), not to syslog targets or ad-hoc files.
3. Wire the collector once per host/stack from the library bundle, used verbatim, never copied: the `log-fluent` compose include with the `x-logging` anchor, the `tier` and `log_format` service labels and the required `GRAYLOG_*`/`HOST_*` variables. Pin the library to a tag; never move or delete a published tag.
4. nginx: log only at the edge, once per request. Include the library's canonical `access_log_format`, never redefine it; `remote_addr` must be the real client (trust the proxy via `set_real_ip_from` plus `real_ip_header`); no access or error logging for static files, health or metrics polls; a project nginx behind another nginx uses `access_log off;`. A host nginx without Docker uses the binary agent documented in the library README ("Docker-less hosts").
5. Verify end to end with an authorized synthetic marker or real request through the actual path (including the real client IP for nginx) and read the record back from the store: exactly one record per event, correct level, fields and types, no secrets. Local output alone does not prove delivery.
6. Report which boundary was observed: emission, collector, searchable store.

For generic telemetry design, dashboards and delivery diagnosis use `monitor-telemetry-setup`; this skill covers applying the owner's libraries and rules.
