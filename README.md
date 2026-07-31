# ai-agents-skills

A [Claude Code](https://code.claude.com/docs/en/plugins) plugin that bundles a
set of skills (and hooks) for running Claude Code productively: a kanban
workflow, an autonomous timed task runner, Telegram notifications, and a few
utilities.

This repository also ships a [Codex](https://developers.openai.com/codex/plugins/build)
plugin manifest (`.codex-plugin/plugin.json`) so the same skills can be used
from Codex CLI — see [Install (Codex)](#install-codex) below. Both
integrations share the same `skills/` tree; see [AGENTS.md](AGENTS.md) for the
repo conventions that keep them in sync.

| Skill | What it does |
|-------|--------------|
| **kanban** | Manage a `.claude/kanban/` board in your project: create, start, review, and complete task cards across `grooming → todo → progress → test → ready → done`. |
| **schedule-tasks** | Schedule autonomous `claude` runs of `todo/` cards via `at`/tmux. Each card opens in its own byobu window and self-chains the next card on success. |
| **tg-notify** | Send a Telegram notification with a short report to a **DM, group, or channel** (configurable). Ships hooks that also auto-notify on long task completion and on permission/idle prompts. |
| **tg-notify-timers** | View/tune the tg-notify hook timers (thresholds, delays, debounce) via `TG_NOTIFY_*` env vars in `settings.json`. |
| **tg-report** | Send a structured **completion** or **task** report to a Telegram **notify group** topic (concise/full modes). Routes by keyword; destination/topics from `TELEGRAM_NOTIFY_*` env (separate from the DM hooks); asks if a value is unset — nothing hardcoded. |
| **git-flow** | The shared git core every other git-using skill follows: commit format (`<scope>: …` + `Agent: <zone>` footer), branch model, explicit-path staging, no force-push to default, PR conventions. |
| **git-move** | Move/rename/delete files while preserving git tracking (`git mv`/`git rm` when tracked, else plain `mv`/`rm`). |
| **setup-claude** | Stack-agnostic template to set up Claude Code in any repo: `CLAUDE.md`, sub-agents, skills, `.mcp.json`, `settings.json`, `Makefile`. Token-economy focused. |
| **new-project-docker** | Scaffold any new project Dockerized from day one: `Dockerfile` + `docker-compose.yml` + `Makefile` + fluent-logging wiring. Templates in `templates.md`. |
| **qa-check** | Quality gate before marking a task done: scopes by `git diff`, runs the project's lint/type/test targets via `make`, reports Pass/Fail. Bans the usual "make it pass" anti-patterns; asks for the target mapping on first use. |
| **prepare-pr** | Get a branch ready for review: sanity-check the diff, delegate the gate to `qa-check`, draft a PR description from commits. Draft-only by default (no auto-push/PR), secret-leak guard, no commit trailers. |
| **fluent-logging** | Cross-project structured-logging standard: containers emit JSON to stdout → fluent-bit → Graylog (GELF), via [`xakki/fluent-log`](https://github.com/Xakki/FluentLog). |
| **skill-import** | Discover & import skills from external git repos into a project's `.claude/skills/`, matched to the project (a subagent picks fits from a built catalog); supports updating imported skills. |

## Agents

| Agent | What it does |
|-------|--------------|
| **ai-agents-skills:log-investigator** | Read-only incident triage. Pulls container logs (Portainer), app logs (Graylog), and metrics (Grafana/Prometheus) and returns a focused UTC timeline + likely root cause — not a raw log dump. `model: sonnet`, mutations denied. On first use in a project it **asks** for the service/tag/endpoint context and offers to save it to your `.claude/`. |
| **ai-agents-skills:db-schema** | Read-only DB schema introspection. Returns concise `table → columns → PK → indexes → FKs` summaries from the live DB, migrations, or config — always naming the source. `model: sonnet`, mutations/migrations denied. Asks for ORM/stack/paths on first use. |

Agents are auto-discovered from `agents/` (no manifest entry needed) and addressable
as `ai-agents-skills:<name>` (e.g. `ai-agents-skills:log-investigator`).

## Install

As a marketplace from this repo:

```
/plugin marketplace add Xakki/ai-agents-skills
/plugin install ai-agents-skills@ai-agents-skills
```

### Dependency: mempalace

This plugin declares a dependency on the [mempalace](https://github.com/MemPalace/mempalace)
plugin (cross-marketplace). Claude Code resolves a dependency only from a
marketplace you have already added — so add the mempalace marketplace **before**
installing, otherwise the install fails with `dependency-unsatisfied`:

```
/plugin marketplace add MemPalace/mempalace
/plugin marketplace add Xakki/ai-agents-skills
/plugin install ai-agents-skills@ai-agents-skills
```

With the mempalace marketplace present, installing `ai-agents-skills` pulls in
`mempalace` automatically.

Or from a local checkout:

```
/plugin marketplace add /home/xakki/ai-agents-skills
/plugin install ai-agents-skills@ai-agents-skills
```

Verify the manifest and skill frontmatter at any time:

```
claude plugin validate /home/xakki/ai-agents-skills
```

## Install (Codex)

1. Install Codex CLI. The standalone installer is preferred on Linux (no
   Node.js/Homebrew dependency):

   ```
   curl -fsSL https://chatgpt.com/codex/install.sh | sh
   ```

2. Add this repo as a Codex plugin marketplace:

   ```
   codex plugin marketplace add Xakki/ai-agents-skills
   ```

3. Launch `codex`, open the plugin picker, and install/enable
   `ai-agents-skills`:

   ```
   /plugins
   ```

4. Start a **new** Codex session — plugin skills and hooks are loaded at
   session start, so an existing session won't pick them up.

Codex loads hooks from the path declared in `.codex-plugin/plugin.json`
(`./hooks/codex-hooks.json`), not from `hooks/hooks.json` (that file is
Claude Code–only). Plugin-bundled hooks are non-managed, so on first run
Codex prompts you to review and trust them before they execute.

### Verify the Codex install

```
codex plugin marketplace list   # confirms the Xakki/ai-agents-skills source is registered
codex plugin list               # confirms ai-agents-skills is installed/enabled
/plugins                        # same, from inside a Codex session
```

Note: the `mempalace` cross-marketplace dependency declared in
`.claude-plugin/plugin.json` is Claude Code–specific; install
[mempalace](https://github.com/MemPalace/mempalace) separately as a Codex
plugin if you want it there too.

## Layout

```
.
├── .claude-plugin/
│   ├── plugin.json        # Claude Code plugin manifest (only this file lives here)
│   └── marketplace.json   # marketplace entry → source "./" (also read by Codex, legacy-compatible)
├── .codex-plugin/
│   └── plugin.json        # Codex plugin manifest (only this file lives here)
├── AGENTS.md              # Codex instructions: shared skills/, separate hook maps
├── hooks/
│   ├── hooks.json         # Claude Code hooks (auto-registered, 6 events)
│   ├── codex-hooks.json   # same hooks mapped to Codex's event names (see plugin.json → "hooks")
│   └── tg-*.sh
├── skills/
│   ├── kanban/
│   ├── schedule-tasks/
│   ├── tg-notify/         # SKILL.md + tg-notify.sh + runtime/context helpers + .env.example
│   ├── tg-notify-timers/
│   ├── tg-report/         # completion/task reports → tg-notify, topics from env
│   ├── git-flow/          # shared git core (commit/branch/PR conventions)
│   ├── git-move/
│   ├── setup-claude/
│   ├── new-project-docker/
│   └── fluent-logging/
└── scripts/               # runners used by schedule-tasks (run from the plugin cache)
```

For Claude Code, the skills are auto-discovered from `skills/`, and the hooks
from `hooks/hooks.json` — no `skills` or `hooks` field in
`.claude-plugin/plugin.json` is needed. The Codex manifest
(`.codex-plugin/plugin.json`) declares both explicitly: `"skills": "./skills/"`
and `"hooks": "./hooks/codex-hooks.json"`, so Codex loads the same skills but
its own hook map instead of `hooks/hooks.json`.

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

#### Two destinations: DM hooks vs. report group

`tg-notify` (and its hooks) use **`TELEGRAM_CHAT_ID`** — typically your **DM**, so
"task finished / needs attention" pings reach you privately. The **`tg-report`**
skill sends explicit, on-request reports to a separate **`TELEGRAM_NOTIFY_*`**
destination — a **group with topics**:

| Var | Purpose |
|---|---|
| `TELEGRAM_NOTIFY_CHAT_ID` | Report group/supergroup id (e.g. `-100…`). |
| `TELEGRAM_NOTIFY_COMPLETION_THREAD` | Forum topic for completion reports. |
| `TELEGRAM_NOTIFY_TASK_THREAD` | Forum topic for task reports. |

Keep these out of `TELEGRAM_CHAT_ID` — topics need a group, and the DM is for the
hooks. For a single user, the `TELEGRAM_NOTIFY_*` vars sit nicely in
`~/.claude/settings.json` (`env` block); the bot token stays in the chmod-600
creds file. If `tg-report` finds a required value unset, it **asks** rather than
sending blind.

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

## Recommendation skills

- impeccable (for landings) `npx -y skills add pbakaus/impeccable --skill impeccable --agent claude-code -g`
- task observer `npx -y skills add rebelytics/one-skill-to-rule-them-all --skill task-observer --agent claude-code -g`

## Contributing — when to migrate a skill here

A debugged, **universal** skill / agent / rule belongs in this plugin. Criteria:
it works correctly **and** carries no personal data. Parameterize it via env/config
following the `tg-notify` pattern:

- secrets in `~/.config/<tool>/.env` (chmod 600) + a placeholder `.env.example` in git;
- the skill body references env vars only — no hardcoded chat ids, threads, tokens,
  host paths, or other users' paths;
- in-repo paths use `${CLAUDE_PLUGIN_ROOT}`, never `~/.claude/...`.

After moving a skill: commit + push → force a plugin update → verify the new
`gitCommitSha` (auto-update keys off the SHA, not the manifest `version`) → only
then delete the local duplicate from `~/.claude/skills/`. Host-/secret-/project-
specific material stays local.

## License

MIT — see [LICENSE](LICENSE).
