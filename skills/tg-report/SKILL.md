---
name: tg-report
description: Sends a structured Telegram report (completion or task topic) via tg-notify. Triggers — RU "Отправить отчёт о завершении", "Отправить отчёт", "Отчёт в TG", "Отправь отчёт в ТГ", "отчёт в телегу", "Отчёт по задаче"; EN "Send completion report", "Send task report", "Send TG report", "Report to telegram". Default — concise (one message); "полный отчёт" / "full report" → full mode (auto-split).
---

# tg-report

Thin wrapper around `${CLAUDE_PLUGIN_ROOT}/skills/tg-notify/tg-notify.sh` that routes to one of two forum topics and enforces a length budget in concise mode.

## When to invoke

User-triggered only. Treat any trigger as explicit Telegram-send authorization — ignore the 20-minute threshold of `tg-notify`.

## Routing — pick topic by keyword

- Request contains **«задача» / «по задаче» / "task"** → **task topic** (`TELEGRAM_NOTIFY_TASK_THREAD`).
- Otherwise (plain «отчёт» / «о завершении» / "completion") → **completion topic** (`TELEGRAM_NOTIFY_COMPLETION_THREAD`).

If genuinely ambiguous, ask the user.

## Modes

| Mode | Trigger | Budget |
|------|---------|--------|
| **Concise** (default) | plain "Отправить отчёт" / "Send report" | ≤ 3500 chars (title + body). Rewrite for density if over. |
| **Full** | "полный отчёт" / "full report" | No cap; script auto-splits at 4000 chars. |

## Configuration

See [reference.md](reference.md) for env-resolution details, report structure, and status semantics.

`TELEGRAM_BOT_TOKEN` is shared with tg-notify (read from `~/.config/tg-notify/.env`). Reports need three additional vars:

| Var | Purpose |
|-----|---------|
| `TELEGRAM_NOTIFY_CHAT_ID` | Report destination — the group/supergroup id (e.g. `-100…`). |
| `TELEGRAM_NOTIFY_COMPLETION_THREAD` | Forum topic id for completion reports. |
| `TELEGRAM_NOTIFY_TASK_THREAD` | Forum topic id for task reports. |

**Critical:** `TELEGRAM_CHAT_ID` is your private DM — never fall back to it for reports.  
**Critical:** If destination or thread is unset → **ask the user**, offer to persist in `~/.claude/settings.json` `env` block.

## How to invoke

```bash
TG="${CLAUDE_PLUGIN_ROOT}/skills/tg-notify/tg-notify.sh"
ENV_FILE="${TG_NOTIFY_ENV:-${XDG_CONFIG_HOME:-$HOME/.config}/tg-notify/.env}"

# capture process env FIRST (settings.json wins over .env)
CHAT="${TELEGRAM_NOTIFY_CHAT_ID:-}"
THREAD="${TELEGRAM_NOTIFY_COMPLETION_THREAD:-}"   # or TASK_THREAD for task reports

# source creds file for bot token + fallback for any unset NOTIFY vars
[ -f "$ENV_FILE" ] && { set -a; . "$ENV_FILE"; set +a; }
CHAT="${CHAT:-${TELEGRAM_NOTIFY_CHAT_ID:-}}"
THREAD="${THREAD:-${TELEGRAM_NOTIFY_COMPLETION_THREAD:-}}"  # or TASK_THREAD

# if CHAT empty → ask the user, don't send to the DM
[ -z "$CHAT" ] && { echo "TELEGRAM_NOTIFY_CHAT_ID unset — ask the user"; exit 1; }

ARGS=(-s ok -p plain -c "$CHAT")
[ -n "$THREAD" ] && ARGS+=(-T "$THREAD")

# concise (default): inline body
"$TG" "${ARGS[@]}" -t "server/repo: краткий заголовок" -m "<body ≤3500 chars>"

# full mode: from file (auto-splits into chunks)
"$TG" "${ARGS[@]}" -t "server/repo: заголовок" -f /tmp/report.txt
```

For all tg-notify.sh flags (`-t/-m/-f/-s/-p/-c/-T/-M/-q`), see [../tg-notify/reference.md](../tg-notify/reference.md).

## Self-check before sending

1. Routing correct? (задача/task → task thread, else completion)
2. `TELEGRAM_NOTIFY_CHAT_ID` + right thread set? If not — ask user.
3. Title ≤70 chars (`server/repo: outcome`)?
4. Concise: `len(title) + len(body) ≤ 3500`?
5. Commit/PR/paths/ports included where relevant?
6. Follow-ups / risks marked ⚠️ at the end?
7. Correct `-s` flag (ok/warn/fail/info)?
