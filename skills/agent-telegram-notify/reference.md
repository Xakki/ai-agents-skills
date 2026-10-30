# agent-telegram-notify — reference

Read this when you're actually sending: configuration, flags, conventions, edge cases.

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
| `TG_NOTIFY_ENABLED` | Export `0`, `false`, `no`, or `off` in the agent process to disable Telegram lifecycle hooks; defaults to enabled. This does not disable an explicitly invoked sender or cancel an already scheduled process. |

The lifecycle hooks read `TG_NOTIFY_ENABLED` from their inherited process
environment before loading runtime files. Setting it only in the sender's
credential file does not disable the hooks. The sender requires `curl` and
`python3`, uses a fixed Telegram HTTPS endpoint without redirect following,
and sends credentials and text to curl through file descriptors/stdin.

**Destination = `TELEGRAM_CHAT_ID`:**
- **Private chat (DM):** your numeric user id, e.g. `123456789`.
- **Group / supergroup:** the negative id, e.g. `-1001234567890`.
- **Channel:** the channel id (`-100…`) or public `@username`, e.g. `@my_channel`.

The bot must be a member of the destination (admin for channels). For a group topic, also set
`TELEGRAM_THREAD_ID`. Per-call you can override with `-c CHAT_ID` / `-T THREAD_ID`.

State, logs and failed payloads live outside the plugin directory; use the
runtime-provided writable directory or explicitly set `TG_NOTIFY_HOME`.

## Flags

| Flag | Purpose |
|---|---|
| `-t TITLE` | Title (bold). |
| `-m TEXT` | Body inline; visible in the caller's process arguments. Prefer stdin for private content. |
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

- Use a short action-oriented title without secrets; title flags are visible in the caller's process arguments.
- The body is the *report* — what you did, what changed, timings. Plain text or simple bullets.
- Pick `-s` carefully: `ok` for success, `fail` for genuine failures, `warn` partial, `info` neutral.
