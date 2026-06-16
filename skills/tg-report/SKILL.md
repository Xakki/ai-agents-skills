---
name: tg-report
description: Send a structured Telegram report for the current task to a configurable topic — completion report OR task report. Trigger phrases — RU "Отправить отчёт о завершении", "Отправить отчёт", "Отчёт в TG", "Отправь отчёт в ТГ", "Отчёт по задаче"; EN "Send completion report", "Send task report", "Report to telegram". Default mode is concise (one Telegram message). If the user says "полный отчёт" / "full report" — produce a full report (auto-split allowed).
---

# tg-report

Sends a structured report for the current Claude session/task to Telegram via the
`tg-notify` sender. One skill, two destinations chosen by the request wording:

- **Completion report** — task is finished → the *completion* topic.
- **Task report** — progress/result on a specific task → the *task-reports* topic.

It is a thin wrapper around `${CLAUDE_PLUGIN_ROOT}/skills/tg-notify/tg-notify.sh`
that picks the topic from env and enforces a length budget by default. No chat id
or thread is hardcoded — everything comes from config (see **Configuration**).

## When to invoke

User-triggered only. Treat any trigger as explicit Telegram-send authorization
regardless of task duration (ignore the 10-minute rule of `tg-notify`).

Triggers (RU/EN):
- «Отправить отчёт о завершении» / «Отправь отчёт о завершении»
- «Отправить отчёт» / «Отчёт в TG» / «отчёт в телегу»
- «Отправь отчёт в ТГ» / «Отправить отчёт в ТГ»
- «Отчёт по задаче» / «Отчёт по задаче в ТГ»
- "Send completion report" / "Send task report" / "Report to telegram" / "Send TG report"

## Routing rule — pick the topic by keyword

The two report kinds share near-identical triggers, so the **wording decides the
destination**. Apply this rule explicitly; do not route arbitrarily:

- Request contains **«задача» / «по задаче» / "task"** → **task report** (task topic).
- Otherwise (plain «отчёт» / «о завершении» / "completion") → **completion report**
  (completion topic).

If genuinely ambiguous, ask the user which topic.

## Two modes

| Mode | Trigger | Length budget |
|------|---------|---------------|
| **Concise** (default) | "Отправить отчёт" / "Отправь отчёт в ТГ" and similar | One TG message, ≤ 3500 chars total (title + body). |
| **Full** | "полный отчёт" / "полный отчёт по задаче" / "Send full report" | No hard cap. `tg-notify` auto-splits into chunks. |

If the natural concise report exceeds the budget, tighten it *before* calling the
script — drop verbose logs, keep only outcomes, key numbers, paths, commit hashes,
URLs, and any warnings/follow-ups. Do not silently truncate; rewrite for density.

## Configuration

Destination and topics come from the **environment** — never committed. The skill
reads the same creds file as `tg-notify` (`~/.config/tg-notify/.env`, chmod 600;
override path with `$TG_NOTIFY_ENV`). Exported env vars win over the file.

| Var | Purpose | Default |
|---|---|---|
| `TG_REPORT_CHAT_ID` | Override destination chat for reports. | `TELEGRAM_CHAT_ID` (tg-notify) |
| `TG_REPORT_COMPLETION_THREAD` | Forum topic for **completion** reports. | `TELEGRAM_THREAD_ID` (tg-notify) |
| `TG_REPORT_TASK_THREAD` | Forum topic for **task** reports. | falls back to completion thread |

`TELEGRAM_BOT_TOKEN` + `TELEGRAM_CHAT_ID` come from the `tg-notify` config as usual.
If `TG_REPORT_TASK_THREAD` is unset, task reports land in the completion topic —
set it so they go to the right place.

## Report structure

Title (≤70 chars, action-oriented): `<server/repo/project>: <что сделано>`
- completion e.g. `<service>: <короткое что сделано>`
- task e.g. `dev.sa: pagespeed CWV — fix CLS=0.39, fonts preload`

Body (concise mode):
- 1 line per outcome, prefix with ✅ / ⚠️ / ❌.
- Include commit hash / branch / PR URL if any.
- Include touched paths, services, ports, URLs.
- End with a ⚠️ block if any follow-up / risk needs the user's attention.
- Skip narrative ("я сделал…", "затем я…"). Just facts.

Body (full mode):
- Same structure plus diagnostics: errors encountered, root causes, configuration
  paths touched, before/after values, log excerpts.

### Optional mention

If the user includes `@username`, place it as the **first line of the body** and use
`-p plain` so Telegram parses the mention (HTML mode wraps the body in `<pre>` and
breaks it).

## Status flag (`-s`)

- `ok` — everything succeeded / задача выполнена.
- `warn` — succeeded with caveats / manual follow-up needed / partial.
- `fail` — task did not complete.
- `info` — neutral status update (rare).

## How to invoke

Resolve the topic from env, then call the sender. The snippet mirrors how
`tg-notify` resolves its creds file, so the report reads the same config.

```bash
TG="${CLAUDE_PLUGIN_ROOT}/skills/tg-notify/tg-notify.sh"
ENV_FILE="${TG_NOTIFY_ENV:-${XDG_CONFIG_HOME:-$HOME/.config}/tg-notify/.env}"
[ -f "$ENV_FILE" ] && { set -a; . "$ENV_FILE"; set +a; }

# Pick the topic by report kind:
#   completion → TG_REPORT_COMPLETION_THREAD (default: TELEGRAM_THREAD_ID)
#   task       → TG_REPORT_TASK_THREAD       (default: completion thread)
THREAD="${TG_REPORT_COMPLETION_THREAD:-${TELEGRAM_THREAD_ID:-}}"                       # completion
# THREAD="${TG_REPORT_TASK_THREAD:-${TG_REPORT_COMPLETION_THREAD:-${TELEGRAM_THREAD_ID:-}}}"  # task

ARGS=(-s ok -p plain)
[ -n "${TG_REPORT_CHAT_ID:-}" ] && ARGS+=(-c "$TG_REPORT_CHAT_ID")
[ -n "$THREAD" ] && ARGS+=(-T "$THREAD")

# Concise (default): title + body inline
"$TG" "${ARGS[@]}" -t "<server/repo>: <краткий заголовок>" -m "<body ≤3500 chars>"

# With mention (first line of body):
"$TG" "${ARGS[@]}" -t "<server/repo>: <заголовок>" -m "@username

<body>"

# Full mode (no length cap, auto-split): body from file
"$TG" "${ARGS[@]}" -t "<server/repo>: <заголовок>" -f /tmp/report.txt
```

## Self-check before sending

1. Routing: does the chosen topic match the keyword rule (задача/task → task topic)?
2. Title ≤70 chars, names the server/repo + outcome.
3. Concise mode: `len(title) + len(body) ≤ 3500`? If not, tighten.
4. Body includes commit / PR URL / paths / ports actually relevant to the reader.
5. Follow-ups / risks marked with ⚠️ at the bottom.
6. Right `-s` flag (ok/warn/fail/info).

If any answer is no, fix before invoking the script.
