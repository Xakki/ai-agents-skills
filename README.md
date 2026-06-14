# ai-agents-skills

A [Claude Code](https://code.claude.com/docs/en/plugins) plugin that bundles
skills for a lightweight kanban workflow — driving it autonomously on a timer —
and Telegram notifications.

| Skill | What it does |
|-------|--------------|
| **kanban** | Manage a `.claude/kanban/` board in your project: create, start, review, and complete task cards across `grooming → todo → progress → test → ready → done`. |
| **schedule-tasks** | Schedule autonomous `claude` runs of `todo/` cards via `at`/tmux. Each card opens in its own byobu window and self-chains the next card on success. |
| **tg-notify** | Send a Telegram notification with a short report to a **DM, group, or channel** (configurable). Ships hooks that also auto-notify on long task completion and on permission/idle prompts. |

## Install

As a marketplace from this repo:

```
/plugin marketplace add Xakki/ai-agents-skills
/plugin install ai-agents-skills@ai-agents-skills
```

Or from a local checkout:

```
/plugin marketplace add /home/xakki/ai-agents-skills
/plugin install ai-agents-skills@ai-agents-skills
```

Verify the manifest and skill frontmatter at any time:

```
claude plugin validate /home/xakki/ai-agents-skills
```

## Layout

```
.
├── .claude-plugin/
│   ├── plugin.json        # plugin manifest (only this file lives here)
│   └── marketplace.json   # marketplace entry → source "./"
├── hooks/
│   ├── hooks.json         # auto-registers the tg-notify hooks (5 events)
│   └── tg-*.sh
├── skills/
│   ├── kanban/
│   ├── schedule-tasks/
│   └── tg-notify/         # SKILL.md + tg-notify.sh + runtime/context helpers + .env.example
└── scripts/               # runners used by schedule-tasks (run from the plugin cache)
```

The skills are auto-discovered from `skills/`, and the hooks from `hooks/hooks.json` —
no `skills` or `hooks` field in `plugin.json` is needed.

## Usage

- **kanban** triggers on task-management requests ("create a task", "what's in
  progress", "mark done"). It operates on `.claude/kanban/` in your *current*
  project; the board is created on first use.
- **schedule-tasks** triggers on "schedule tasks" / "запланируй задачи". It needs
  `atd` active and a byobu/tmux session, and reads cards from
  `.claude/kanban/todo/` in your current project.
- **tg-notify** triggers on "send to telegram" / "notify in TG" / "ping me when
  done", and auto-sends via its hooks for long task completion and
  permission/idle prompts. See [tg-notify](#tg-notify) for setup.

### schedule-tasks & the plugin cache

`schedule-tasks` invokes the runner scripts from `${CLAUDE_PLUGIN_ROOT}/scripts/`
(the installed plugin's cache), not from your repo. The scripts derive the
target repo from the task-file path they're given
(`<repo>/.claude/kanban/<stage>/<name>.md`), so they work from any project
without per-repo configuration. Your kanban board still lives in your project
under `.claude/kanban/`.

### tg-notify

The bot token and destination come from the **environment** — nothing secret is
committed. Configure once, then both the manual sender and the hooks use it.

1. Create a bot with [@BotFather](https://t.me/BotFather) and copy its token.
2. Copy the template and fill it in (chmod 600):

   ```
   mkdir -p ~/.config/tg-notify
   cp "${CLAUDE_PLUGIN_ROOT}/skills/tg-notify/.env.example" ~/.config/tg-notify/.env
   chmod 600 ~/.config/tg-notify/.env
   $EDITOR ~/.config/tg-notify/.env
   ```

   (Exported env vars `TELEGRAM_BOT_TOKEN` / `TELEGRAM_CHAT_ID` / … override the file.)

3. Choose the destination with **`TELEGRAM_CHAT_ID`** — this is the single switch
   between a private chat, a group, and a channel:

   | Destination | `TELEGRAM_CHAT_ID` | Notes |
   |---|---|---|
   | Private chat (DM) | numeric user id, e.g. `123456789` | start a chat with the bot first |
   | Group / supergroup | negative id, e.g. `-1001234567890` | add the bot to the group; set `TELEGRAM_THREAD_ID` for a forum topic |
   | Channel | `-100…` id or `@username` | add the bot as an **admin** |

The hooks fire on these events (auto-registered from `hooks/hooks.json`):

| Event | Hook | Notice |
|---|---|---|
| `Stop` | `tg-on-stop.sh` | "✅ Задача завершена" for turns longer than ~20 min (overridable). |
| `Notification` | `tg-on-notification.sh` | "🔐 Требуется разрешение" / "⏰ Ожидает ввода" on permission/idle. |
| `UserPromptSubmit` | `tg-prompt-start.sh` | records task start; cancels stale pending notices. |
| `PreToolUse`, `SessionEnd` | `tg-cancel-pending.sh` | cancels pending notices when the turn resumes/ends. |

Each notice is **scheduled with a delay** and cancelled if you become active before
it fires, so you only get pinged when you've genuinely stepped away. Thresholds and
delays are overridable via env (`TG_NOTIFY_STOP_THRESHOLD`, `TG_NOTIFY_DELAY`, …).
State, logs, and undelivered payloads live under `$TG_NOTIFY_HOME`
(default `$CLAUDE_PLUGIN_DATA`, else `~/.local/state/tg-notify`).

## Requirements

- `schedule-tasks`: `atd` running (`systemctl is-active atd`), `at`/`atq`/`atrm`,
  a tmux/byobu session, and `claude` on `PATH`.
- `tg-notify`: `curl`, `jq`, `python3`, and (for the context header in hooks) a
  tmux/byobu session. A `TELEGRAM_BOT_TOKEN` + `TELEGRAM_CHAT_ID` as above.

## License

MIT — see [LICENSE](LICENSE).
