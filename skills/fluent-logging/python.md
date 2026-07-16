# Python — structured JSON to stdout

Goal: the container writes **one JSON line per record to stdout/stderr**. The global
`json_default` fluent-bit parser unpacks the JSON automatically (on all `gl.*`),
`log_format` can be left unset → `gl.auto`. Fields — per the contract in [rules.md](rules.md).
Working reference: `<project>/app/logging_setup.py`.

## Minimal requirements
1. **One setup across ALL entrypoints** (web/worker/cron/scripts) — a single
   `configure_logging()` module, don't copy-paste `basicConfig` across files.
2. **JSON formatter** on the root handler. Either `python-json-logger` or your own
   `logging.Formatter` serializing `{datetime, level, level_name, message,
   context:{...}}`. JSON escapes control chars itself (protection against log injection).
3. **Secret-redaction filter** on the root HANDLER (not on the logger — otherwise it misses
   propagated records from child loggers like httpx/telethon/sqlalchemy).
4. **Levels** per the decision tree ([rules.md](rules.md)); prod default `info`.
5. **Business values** — in `extra`/context, not in an f-string: `log.info("order paid",
   extra={"context": {"order_id": oid, "amount_cents": 4999, "tag": "billing"}})`.

## Secret redaction (pattern)
Common leak: httpx/SDK log a URL with the token in the path (Telegram
`api.telegram.org/bot<id>:<secret>/method`). The filter cuts the secret BEFORE emit:

```python
import logging, re
_TG_TOKEN = re.compile(r"(\d{6,}):[A-Za-z0-9_-]{35,}")   # bot_id is public, the secret isn't

class RedactSecrets(logging.Filter):
    def filter(self, record):
        try: msg = record.getMessage()
        except Exception: return True
        if ":" in msg and _TG_TOKEN.search(msg):
            record.msg = _TG_TOKEN.sub(r"\1:<REDACTED>", msg); record.args = ()
        return True

def configure_logging(level=logging.INFO):
    logging.basicConfig(level=level, format="%(asctime)s %(name)s %(levelname)s: %(message)s")
    for h in logging.getLogger().handlers:
        if not any(isinstance(f, RedactSecrets) for f in h.filters):
            h.addFilter(RedactSecrets())
```
Extend the ban-list per project (Authorization headers, API keys, passwords, PHPSESSID…).
**PII-regression test is mandatory:** a known (fake) secret must NOT reach the output.

## Noisy libraries
- `httpx`/`uvicorn`/`telethon`/`sqlalchemy` write to their own loggers → propagate to root →
  redaction applies (filter on the root handler). Raise noisy loggers to WARNING,
  if INFO isn't needed.
- **arq** (worker): the CLI attaches its own handler to the `arq` logger → double output
  together with root. Silence it **at module level** (before the worker starts): `logging.getLogger("arq").
  propagate = False` (the «Starting worker» banner is logged before on_startup — too late in on_startup).

## Best-effort and the DB pool
- `fluentd-async: true` → an unavailable socket doesn't crash the app (see integration.md).
- **Switching the DB to fluentd = postgres recreation = a bounce** → the SQLAlchemy pool gets
  dead connections. Mandatory `create_async_engine(..., pool_pre_ping=True,
  pool_recycle=1800)` — otherwise a cascade "Can't reconnect until invalid transaction is
  rolled back". This applies to ANY DB restart (deploy), not just enabling logs.

## NDJSON file (stdout alternative)
If logs go to a file, not stdout: write `<JSON_LOG_PATH>/<service>.ndjson`, one JSON per
line; fluent-bit tails `/var/log/json/*.ndjson`, filename = `docker_service`.
Use when stdout is taken (legacy) — by default stdout is preferred (12-factor).
