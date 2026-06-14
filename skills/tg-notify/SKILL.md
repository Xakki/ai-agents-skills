---
name: tg-notify
description: Send a Telegram notification with a short report — to a private chat, group, or channel (configurable). ONLY auto-trigger when a task that just finished took longer than 10 minutes of wall-clock time (deploy, big rsync/backup, large build, batch job, scheduled run) — the user is unlikely to still be watching the terminal. The 10-minute threshold may be bypassed only when the user explicitly asks ("send to telegram", "notify in TG", "ping me when done", or similar) or when invoked from a scheduled / background job that is expected to report regardless of duration.
---

# tg-notify

Sends a Telegram message to a configurable destination (DM, group, or channel) via a bot.
This plugin also ships **hooks** (see `../../hooks/`) that auto-send a "task finished" notice
for long turns and a "needs attention" notice on permission/idle prompts — those run
automatically once configured; this skill is the **manual** sender you invoke on request.

## When to use (manual sends)

**Hard rule: 10-minute minimum for auto-sends.** Only auto-send if the operation that just
finished consumed **more than 10 minutes**. For anything shorter, just answer in the terminal.

Trigger cases:
- A long-running operation (>10 min) just finished — send a short status report with timing.
- The user explicitly asks for a Telegram notification, summary, or ping (any duration).
- A scheduled / background job needs to report results (any duration).

Track duration honestly with `SECONDS=0; <command>; dur=$SECONDS` so the threshold check is real.

## Configuration

Credentials and destination come from the **environment** — never committed. Set them either as
exported env vars or in a creds file (chmod 600) at `~/.config/tg-notify/.env`
(override path with `$TG_NOTIFY_ENV`). Copy `.env.example` to start. Exported vars win over the file.

| Var | Purpose |
|---|---|
| `TELEGRAM_BOT_TOKEN` | Bot token from @BotFather (required). |
| `TELEGRAM_CHAT_ID` | Destination (required) — **switch DM ↔ group ↔ channel here**. |
| `TELEGRAM_THREAD_ID` | Forum topic id (optional; sent only when non-empty). |
| `TELEGRAM_MENTION` | Mention prepended to every message (optional; empty = none). |

**Destination = `TELEGRAM_CHAT_ID`:**
- **Private chat (DM):** your numeric user id, e.g. `123456789`.
- **Group / supergroup:** the negative id, e.g. `-1001234567890`.
- **Channel:** the channel id (`-100…`) or public `@username`, e.g. `@my_channel`.

The bot must be a member of the destination (admin for channels). For a group topic, also set
`TELEGRAM_THREAD_ID`. Per-call you can override with `-c CHAT_ID` / `-T THREAD_ID`.

State/logs/failed payloads live under `$TG_NOTIFY_HOME` (default `$CLAUDE_PLUGIN_DATA` or
`~/.local/state/tg-notify`), outside the plugin directory.

## How to invoke

```bash
TG="${CLAUDE_PLUGIN_ROOT}/skills/tg-notify/tg-notify.sh"

# Short status (title only)
"$TG" -s ok -t "Backup завершён" -m "wephost: 64 GiB, 12m 03s"

# Title + multi-line body via stdin (preferred for reports)
{
  echo "rsync /home/wephost: 64.0 GiB, 12m 03s"
  echo "Все сервисы запущены."
} | "$TG" -s ok -t "saFin: миграция завершена"

# Send to a different destination than the default (e.g. a channel)
echo "released v1.2.3" | "$TG" -s ok -t "Deploy" -c "@my_channel"
```

## Flags

| Flag | Purpose |
|---|---|
| `-t TITLE` | Title (bold). |
| `-m TEXT` | Body inline. |
| `-f FILE` | Body from file. |
| stdin | Body from stdin if `-m`/`-f` not given and stdin is a pipe. |
| `-s ok\|fail\|warn\|info` | Adds an emoji to the title. |
| `-p plain\|html\|markdown` | Parse mode (default `html` — body wrapped in `<pre>`). |
| `-c CHAT_ID` | Override destination. |
| `-T THREAD_ID` | Override topic/thread id. |
| `-M MENTION` | Override mention (empty string disables). |
| `-q` | Quiet on success. |

Body is auto-split into ≤4000-char chunks if too long for one Telegram message.

## Conventions

- Title under ~70 chars, action-oriented (`saFin: rsync xakki завершён`, `prom rules reload failed`).
- The body is the *report* — what you did, what changed, timings. Plain text or simple bullets.
- Pick `-s` carefully: `ok` for success, `fail` for genuine failures, `warn` partial, `info` neutral.
