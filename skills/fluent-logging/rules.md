# Log rules (digest of LaraLog `docs/LoggingRules.ru.md`)

Principles are language-agnostic (PHP/Python/Node). Source:
<https://raw.githubusercontent.com/Xakki/LaraLog/refs/heads/main/docs/LoggingRules.ru.md>

## Base principles
1. **A log is an API.** Breaking a field name = breaking REST. Names are stable.
2. **Structure over prose.** A record is JSON with stable names; `message` for
   eyes, search — by `context`/`extra`.
3. **Log once, at the boundary.** No catch-log-rethrow at every level.
4. **Logging never fails the request.** Best-effort; sink unavailable → request OK.
5. **Cardinality:** per-request-varying data goes in FIELDS, not index labels.

## What NOT to log (violation = security incident)
Passwords/hashes/reset tokens; API keys, bearer/refresh; session IDs (`PHPSESSID`,
`Cookie: session=`); full payment data (PAN/CVV); gov IDs (SNILS/INN/passport/SSN),
medical data; bulk full PII; raw bodies of endpoints carrying these. **Redact at the
process boundary**, placeholders `***`/`[redacted]`/`sha256:<8 chars>`. Careful with
HTTP dumps, traces with args, ORM bindings, exception messages with user input.

## Levels — decision tree
- Service not serving requests → **emergency**
- Data corrupted/lost → **critical** (immediate alert)
- Operation failed, no recovery, reached the user → **error** (alert from 1%)
- Failure absorbed but action needed → **warning** (from 5%)
- Odd/suspicious/auto-corrected → **notice** (from 10%)
- Normal business event → **info**
- Useful only when reproducing a bug → **debug** (off in prod)

Rules: **WARN with no concrete action → NOTICE** (test: "what should the dev
do?"; "happens sometimes" → notice, else warning-fatigue). **WARN** = the system
absorbed the failure (fallback/cache, user request succeeded); **ERROR** = the failure
escaped outward (retries exhausted, 5xx). Intermediate retries → warning, final → error.
Numeric severities: debug 100, info 200, notice 250, warning 300, error 400,
critical 500, alert 550, emergency 600. Prod default — `info`; debug is enabled
locally/per-instance/for an incident, NEVER globally.

## Record shape
**Top-level (contract):** `datetime` (RFC3339), `level` (int), `level_name`
(lowercase), `channel`, `message` (short sentence, no interpolation),
`context` (per-event), `extra` (stable per process).
- **extra:** `app_name`, `app_env`, `app_ver`, `tier`, `release_tag`, load_avg…
- **context:** `log_type`, `request_id` (UUID, carried across queues/outbound),
  `trace_id`/`span_id`, `user_id`, `file`/`line`, `exception` (FQN), `tag`, business IDs.
- **log_type:** `logger` (explicit call), `trigger` (runtime/deprecation), `exception`
  (uncaught/logged), `fatal` (shutdown/OOM/timeout). Alert on `exception,fatal`.
- **Business IDs in `context`, not in `message`.** Type discipline: `*_id/*_count` → int;
  `is_*/has_*` → bool; money → int in minor units (`amount_cents`), not float;
  durations → int ms. Names — `snake_case`, prefixes `app_*`/`http_*`/`db_*`/`queue_*`.
- **Limits:** `message` ~3 KB; whole line <16 KB; trace 5/10/20 frames (Warn/Error/Crit);
  trace args 128 chars; truncation marker `…`.

## Correlation
3 IDs: `trace_id` (whole transaction, OTel), `span_id` (unit of work), `request_id`
(one HTTP request, `X-Request-ID`). Inject into scope once per entrypoint (MDC),
don't pass by hand. Every entrypoint — an `entry`/`exit` pair (`duration_ms`, `success`,
`status_code`). Outbound HTTP forwards `X-Request-ID`/`traceparent`; a queue job
serializes the IDs into the payload.

## Special scenarios
- **Exceptions:** log once at the top with business context. Fields: `exception`
  (FQN, not message), `exception_code`, `file:line`, `trace`, `prev` chain. The exception
  message is suspect (PII/log-injection): store FQN+code, message only outside prod or
  sanitized.
- **External calls:** for each — `info` without payload, fields `target` (name, not URL),
  `method`, `path`, `response_code`, `latency_ms`, `attempt`. Failure progression:
  1st (retry starts) → notice; retry → warning; max_attempts → error.
- **Slow SQL:** channel `tag:sql`, fields `db_query` (truncated), `db_table`, `db_time_ms`;
  NEVER raw bindings in prod. N+1 (>50 identical within one request_id) → warning.
- **Audit** (who/what/when/result) — SEPARATE sink/index/retention, durable
  append-only, no sampling, sync. Don't mix with operational. Details — §6.5 of the doc.

## Antipatterns
Interpolation in message; logging the exception at every catch; `throw` without `previous`;
`error("something happened")` (message = noun+verb, values in context);
warning on an always-taken path; `info` in a tight loop (sample/debug);
`request_id`/`user_id` as labels (→ fields); logging the full body (→ `size`/`content_type`);
catch-and-swallow with no log; `print_r`/`var_export` in message; sync write on the request path.

## Transport
12-factor: the app writes JSON to **stdout/stderr**, not caring about routing/storage →
the agent (fluent-bit) tails → pipeline (Graylog). Backpressure at the agent, not in the app.
Environments isolated (dev/staging NOT in the same index as prod). Sampling — only info/debug
(notice+ always in full); sticky-per-trace — the de facto standard; don't sample audit.

## Lifecycle
- **Linter in CI:** ban interpolation in message, `print_r`/`var_export`, ban-list keys.
- **PII regression tests:** known secrets do NOT reach the logs (mandatory).
- **Field catalog** (`docs/log-fields.yml`) — source of truth; whitelist for `tag`
  (auth, billing, sql, queue, upstream, entrypoint, audit, cron). Renaming a field =
  dual-write ≥2 releases.
- **Alerts:** critical/emergency immediately; error >1% & count≥5; warning >5% & count≥20;
  notice >10% & count≥50; 5 min window. Target metric — MTTR.
