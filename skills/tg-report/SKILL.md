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

Reports go to a **separate destination from the auto-notify hooks**. The hooks
(`tg-notify` Stop/Notification) ping you privately via `TELEGRAM_CHAT_ID` (a DM).
Reports are an explicit, on-request send to a *group with topics* — so they use
their own `TELEGRAM_NOTIFY_*` family and never inherit the DM chat.

| Var | Purpose |
|---|---|
| `TELEGRAM_NOTIFY_CHAT_ID` | Report destination — the group/supergroup id (e.g. `-100…`). Passed via `-c`. |
| `TELEGRAM_NOTIFY_COMPLETION_THREAD` | Forum topic id for **completion** reports. Passed via `-T`. |
| `TELEGRAM_NOTIFY_TASK_THREAD` | Forum topic id for **task** reports. Passed via `-T`. |

`TELEGRAM_BOT_TOKEN` comes from the `tg-notify` config (`~/.config/tg-notify/.env`,
chmod 600). The `TELEGRAM_NOTIFY_*` values may be exported, set in
`~/.claude/settings.json` (`env` block), or placed in the creds file. Exported env
vars win.

- **`TELEGRAM_CHAT_ID` is the DM** for hooks — do **not** fall back to it for
  reports. Topics live only in the notify group; sending a thread id to a DM
  silently lands in the wrong place.

### Ask if a needed value is unset — do not send blind

Before sending, check the destination for the chosen report kind:
- completion → needs `TELEGRAM_NOTIFY_CHAT_ID` + `TELEGRAM_NOTIFY_COMPLETION_THREAD`
- task → needs `TELEGRAM_NOTIFY_CHAT_ID` + `TELEGRAM_NOTIFY_TASK_THREAD`

If any required value is empty/unset, **ask the user for it** (use
`AskUserQuestion`) instead of guessing or sending to the DM. Offer to persist the
answer in `~/.claude/settings.json` under the `env` block so it sticks for next
time. Only proceed once the chat id (and thread, for a topic group) is known.

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

Resolve the destination from env, then call the sender. The snippet sources the
`tg-notify` creds file (for the bot token); the `TELEGRAM_NOTIFY_*` values may
come from there or from `settings.json` env.

```bash
TG="${CLAUDE_PLUGIN_ROOT}/skills/tg-notify/tg-notify.sh"
ENV_FILE="${TG_NOTIFY_ENV:-${XDG_CONFIG_HOME:-$HOME/.config}/tg-notify/.env}"
[ -f "$ENV_FILE" ] && { set -a; . "$ENV_FILE"; set +a; }

CHAT="${TELEGRAM_NOTIFY_CHAT_ID:-}"                       # report group (NOT TELEGRAM_CHAT_ID)
THREAD="${TELEGRAM_NOTIFY_COMPLETION_THREAD:-}"           # completion report
# THREAD="${TELEGRAM_NOTIFY_TASK_THREAD:-}"               # task report

# If CHAT (or, for a topic group, THREAD) is empty → ASK the user, don't send blind.
[ -z "$CHAT" ] && { echo "TELEGRAM_NOTIFY_CHAT_ID unset — ask the user"; exit 1; }

ARGS=(-s ok -p plain -c "$CHAT")
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
2. Destination: `TELEGRAM_NOTIFY_CHAT_ID` (+ the right thread) is set? If not — ask the user, don't send to the DM.
3. Title ≤70 chars, names the server/repo + outcome.
4. Concise mode: `len(title) + len(body) ≤ 3500`? If not, tighten.
5. Body includes commit / PR URL / paths / ports actually relevant to the reader.
6. Follow-ups / risks marked with ⚠️ at the bottom.
7. Right `-s` flag (ok/warn/fail/info).

If any answer is no, fix before invoking the script.
