# ai-agents-skills

A cross-agent plugin that bundles skills, specialist prompts, and hooks for
running coding agents productively: a kanban
workflow, an autonomous timed task runner, Telegram notifications, and a few
utilities.

This repository also ships a [Codex](https://developers.openai.com/codex/plugins/build)
plugin manifest (`.codex-plugin/plugin.json`) and repository marketplace
(`.agents/plugins/marketplace.json`) so the same skills can be installed from
Codex CLI — see [Install (Codex)](#install-codex) below — and a
[Cursor](https://cursor.com/docs/reference/plugins) Agent CLI/IDE plugin
manifest (`.cursor-plugin/plugin.json`) — see [Install (Cursor)](#install-cursor)
below — plus a [Hermes Agent](https://hermes-agent.nousresearch.com/docs/user-guide/features/plugins)
plugin (`plugin.yaml` + `__init__.py`) — see [Install (Hermes)](#install-hermes).
All four integrations share the same `skills/` tree; see
[AGENTS.md](AGENTS.md) for the repo conventions that keep them in sync.

| Skill | What it does |
|-------|--------------|
| **kanban** | Manage a `.claude/kanban/` board in your project: create, start, review, and complete task cards across `grooming → todo → progress → test → ready → done`. |
| **knbn** | Portable invocation alias for **kanban**. It loads the canonical Kanban workflow and adds no separate behavior. |
| **epic-lead** | Lead one approved Kanban EPIC through governed integration, review, authorized finalization, and handoff. |
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
| **model-tiers** | Map cheap / standard / judgment work to model slugs via `AI_MODEL_*` env; SessionStart injects tier labels; plugin agents and delegation pick tiers, not hardcoded slugs. |

## Agents

| Agent | What it does |
|-------|--------------|
| **ai-agents-skills:log-investigator** | Read-only incident triage. Pulls container logs (Portainer), app logs (Graylog), and metrics (Grafana/Prometheus) and returns a focused UTC timeline + likely root cause — not a raw log dump. `model:` frontmatter = plugin **standard**-tier default (`sonnet`); override via `AI_MODEL_*` / skill `model-tiers`. Mutations denied. On first use in a project it **asks** for the service/tag/endpoint context and offers to save it to your `.claude/`. |
| **ai-agents-skills:db-schema** | Read-only DB schema introspection. Returns concise `table → columns → PK → indexes → FKs` summaries from the live DB, migrations, or config — always naming the source. `model:` frontmatter = plugin **standard**-tier default (`sonnet`); override via `AI_MODEL_*` / skill `model-tiers`. Mutations/migrations denied. Asks for ORM/stack/paths on first use. |

Claude and Cursor auto-discover agents from `agents/` and address them as
`ai-agents-skills:<name>`. The Codex package exposes the shared `skills/` tree;
`setup-claude` additionally declares a Codex policy that prevents implicit
invocation. The root `agents/` prompts are not declared by its Codex manifest.
Hermes exposes the same prompt bodies as read-only
plugin skills named `ai-agents-skills:agent-<name>` (for example,
`skill_view("ai-agents-skills:agent-log-investigator")`).

## Install (Claude Code)

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

2. Add this GitHub repository as a Codex marketplace, then install its plugin:

   ```
   codex plugin marketplace add Xakki/ai-agents-skills --ref main
   codex plugin add ai-agents-skills@ai-agents-skills
   ```

3. Start a **new** Codex session — plugin skills and plugin metadata are loaded at
   session start, so an existing session won't pick them up.

The Codex manifest explicitly selects `./hooks/codex-hooks.json`, rather than
the Claude Code-specific default `hooks/hooks.json`. Codex requires the user
to review and trust plugin hooks before executing them. Once trusted, these
hooks can send the optional Telegram task-finished and needs-attention
notifications configured by `tg-notify`; review the outbound commands before
trusting them. Root `agents/` prompts remain available to the Claude, Cursor,
and Hermes integrations only.

### Verify the Codex install

```
codex plugin marketplace list   # confirms the GitHub marketplace is registered
codex plugin list               # lists ai-agents-skills in its marketplace snapshot
```

Note: the `mempalace` cross-marketplace dependency declared in
`.claude-plugin/plugin.json` is Claude Code–specific; install
[mempalace](https://github.com/MemPalace/mempalace) separately as a Codex
plugin if you want it there too.

## Install (Prime Agent)

Prime Agent natively installs capability packages from Git. This repository's
`package.json` exposes the shared `skills/` tree, the specialist prompts in
`agents/`, and a Prime lifecycle adapter:

```bash
prime-agent package install git:github.com/Xakki/ai-agents-skills
```

Install only for the current project instead of the user configuration:

```bash
prime-agent package install git:github.com/Xakki/ai-agents-skills --local
```

For reproducibility, pin a tag or commit. Start a fresh Prime Agent session
once installed:

```bash
prime-agent package install git:github.com/Xakki/ai-agents-skills@<tag-or-commit>
prime-agent package list
```

Prime discovers all `skills/*/SKILL.md` files and exposes `agents/*.md` as
prompt templates (for example, `/chore`), rather than as Claude-style named
subagents. The adapter runs the shared abbreviation and model-tier context
injection, task-start, pending-notification cancellation, and delayed
completion-notification hooks. Prime Agent does not expose Claude's
`Notification`/`PermissionRequest` lifecycle events, so its optional Telegram
"needs attention" notice safely degrades; completion notifications still work.

For Prime subagent tiers, set exact model selectors in the environment before
starting Prime Agent, for example `AI_MODEL_CHEAP`, `AI_MODEL_STANDARD`, and
`AI_MODEL_JUDGMENT`. Use values accepted by your `prime-agent model list`;
provider availability is installation-specific.

## Install (Hermes)

Install and explicitly enable the plugin from GitHub:

```bash
hermes plugins install Xakki/ai-agents-skills --enable
```

For a local Git checkout, use a `file://` Git URL (the installer clones the
repository, so uncommitted working-tree changes are not included):

```bash
hermes plugins install file:///path/to/ai-agents-skills --enable
```

Verify discovery and state:

```bash
hermes plugins list --plain --no-bundled
```

Hermes registers all `skills/*/SKILL.md` files read-only under
`ai-agents-skills:<name>`. Plugin skills are explicit loads rather than
slash-command registrations: use `skill_view("ai-agents-skills:knbn")` (or
`skill_view("ai-agents-skills:kanban")`) when you want the workflow. The
built-in `/kanban` board command remains separate. All `agents/*.md` prompts
remain namespaced as `ai-agents-skills:agent-<name>`. You can also load skills
explicitly, for example:

```text
skill_view("ai-agents-skills:knbn")
skill_view("ai-agents-skills:qa-check")
skill_view("ai-agents-skills:epic-lead")
skill_view("ai-agents-skills:agent-db-schema")
```

The Hermes adapter maps `pre_llm_call`, `post_llm_call`, session-finalize, and
session-reset events to the shared abbreviation and Telegram hook behavior.
Hermes does not expose a plugin hook for permission/idle notifications, so that
specific Telegram ping is not wired. `schedule-tasks` and `setup-claude` remain
Claude-specific workflows; `model-tiers` is informational under Hermes because
Hermes subagents inherit the active model rather than accepting a per-call tier.
The mempalace dependency in the Claude manifest is not installed by Hermes.

## Install (Cursor)

1. Install the [Cursor Agent CLI](https://cursor.com/docs/cli) (`cursor-agent`).
2. Register this repo as a plugin marketplace source:

   ```
   cursor-agent plugin marketplace add https://github.com/Xakki/ai-agents-skills
   ```

3. As of this writing, the Cursor CLI has **no non-interactive `plugin
   install` command** (confirmed against `cursor-agent plugin --help` and
   Cursor's own docs/forum, 2026-07-31) — `plugin marketplace add` only
   registers the source. Enable the plugin one of these ways:
   - **Interactive CLI:** run `cursor-agent`, type `/plugin`, open the
     **Marketplace** tab, select `ai-agents-skills`, and press Enter —
     choose **user** scope to make it available in every future session, or
     **project** scope for just this repo.
   - **Cursor IDE:** open **Customize** in the sidebar → **Plugins** → find
     `ai-agents-skills` → install.
   - **Local/dev testing** (no marketplace registration needed): point the
     CLI directly at a checkout of this repo:

     ```
     cursor-agent --plugin-dir /path/to/ai-agents-skills
     ```

4. Verify:

   ```
   cursor-agent plugin marketplace list   # confirms the source is registered
   ```

   In a fresh session, confirm the skills (`skills/`), the 3 agents
   (`agents/*.md`), and the 5 Cursor hook bindings from
   `hooks/cursor-hooks.json` are discoverable — the **Hooks** tab and
   **Customize** panel in Cursor list configured/executed hooks and
   installed skills/agents.

Cursor loads this plugin's skills, agents, and hooks through
`hooks/cursor-hooks.json` (routed through a normalization adapter,
`hooks/cursor-adapter.sh`, since Cursor's hook payload field names differ
from Claude Code's/Codex's). Session-start context injection, prompt-start
bookkeeping, and the "✅ task finished" Telegram ping all work the same as
under Claude Code/Codex. The "🔐 needs your permission" / "⏰ waiting for
input" ping does **not** fire under Cursor — there is no Cursor hook event
for it. See [the design doc](docs/superpowers/specs/2026-07-31-cursor-plugin-design.md#safe-degradation-notification--permissionrequest)
for why.

Note: the `mempalace` cross-marketplace dependency declared in
`.claude-plugin/plugin.json` is Claude Code–specific; install
[mempalace](https://github.com/MemPalace/mempalace) separately for Cursor if
you want it there too.

## Layout

```
.
├── .claude-plugin/
│   ├── plugin.json        # Claude Code plugin manifest (only this file lives here)
│   └── marketplace.json   # marketplace entry → source "./" (also read by Codex, legacy-compatible)
├── .agents/plugins/
│   └── marketplace.json   # Codex repository marketplace → source "./"
├── .codex-plugin/
│   └── plugin.json        # Codex plugin manifest (only this file lives here)
├── .cursor-plugin/
│   ├── plugin.json        # Cursor plugin manifest — declares "hooks": "./hooks/cursor-hooks.json"
│   └── marketplace.json   # marketplace entry → source "./"
├── plugin.yaml             # Hermes plugin manifest
├── __init__.py             # Hermes skill + lifecycle-hook registration adapter
├── after-install.md        # Hermes post-install usage summary
├── AGENTS.md              # Codex instructions: shared skills/, separate hook maps
├── hooks/
│   ├── hooks.json         # Claude Code hooks (auto-registered, 6 events)
│   ├── codex-hooks.json   # Codex event map declared by the Codex manifest
│   ├── cursor-hooks.json  # same hooks mapped to Cursor's event names, via cursor-adapter.sh
│   ├── cursor-adapter.sh  # normalizes Cursor payloads for the shared tg-*.sh / abbr-inject.sh scripts
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
├── statusline/            # opt-in status-line renderers (see statusline/README.md)
│   ├── statusline-command.sh
│   └── subagent-statusline-command.sh
└── scripts/               # runners used by schedule-tasks (run from the plugin cache)
```

## Status line (opt-in)

`statusline/` ships two `bash` + `jq` renderers: a lead row
(`model · launch dir · branch · dirty · ctx% · session tokens · pwd`, where `pwd`
appears only when it differs from the launch dir) and a compact teammate row for
the agent panel. They are **not** auto-registered — copy them to `~/.claude/bin/`
and point `statusLine` / `subagentStatusLine` in `settings.json` at the absolute
path. Full install and verification steps: [statusline/README.md](statusline/README.md).

For Claude Code, the skills are auto-discovered from `skills/`, and the hooks
from `hooks/hooks.json` — no `skills` or `hooks` field in
`.claude-plugin/plugin.json` is needed. The Codex manifest
(`.codex-plugin/plugin.json`) declares `"skills": "./skills/"`; its repository
marketplace (`.agents/plugins/marketplace.json`) points at this plugin root.
It explicitly declares `"hooks": "./hooks/codex-hooks.json"`, so Codex uses
its own event map instead of the Claude Code default. The Cursor manifest
(`.cursor-plugin/plugin.json`) auto-discovers `skills/` and `agents/` the same
way Claude Code does (default folder-based discovery), and declares `hooks`
explicitly (same posture as Codex) pointing at `./hooks/cursor-hooks.json` —
the adapted event map that routes through `hooks/cursor-adapter.sh`.
Hermes loads the root `plugin.yaml` and `__init__.py`; the adapter registers the
same skill files without copying them for namespaced explicit discovery and
loading via `skill_view("ai-agents-skills:<name>")`, and normalizes Hermes
lifecycle callback arguments for the shared Telegram scripts.

### Kanban alias: `knbn`

`knbn` is a second, portable skill name for the canonical `kanban` workflow. It
is a small real `skills/knbn/SKILL.md` forwarding skill—not a symlink—and adds
no independent lifecycle or scripts. The real directory is intentional: Codex
documents linked skill folders, but reliable symlink traversal is not a shared
contract for every supported discovery surface (notably Cursor). Keeping both
names as ordinary skill directories makes plugin installation and discovery
portable across all five integrations.

After installing or updating the plugin, start a fresh session (or use the
runtime's reload action) and use the alias as follows:

| Runtime | Discover / invoke `knbn` |
|---|---|
| Claude Code | Plugin folder discovery exposes the `skills/knbn/` directory; invoke `/knbn` or ask for `knbn`. |
| Codex | The manifest exposes `./skills/`; start a new session and mention `$knbn` (or ask for `knbn`). |
| Cursor | Plugin folder discovery exposes the `skills/knbn/` directory; start a fresh session and invoke or mention `knbn`. |
| Hermes | The adapter registers `ai-agents-skills:knbn`; load it with `skill_view("ai-agents-skills:knbn")`. The built-in `/kanban` board command remains separate. |
| Prime Agent | Its package scanner finds `skills/knbn/SKILL.md`; start a fresh session and use `/skill:knbn` (or ask for `knbn`). |

Do not create downstream symlinks for this alias. Install the plugin normally;
the included real alias directory is the compatible mechanism.

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
   ROOT="${AI_AGENTS_SKILLS_ROOT:-${CLAUDE_PLUGIN_ROOT:-${PLUGIN_ROOT:-${CURSOR_PLUGIN_ROOT:-}}}}"
   cp "$ROOT/skills/tg-notify/.env.example" ~/.config/tg-notify/.env
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

Under Cursor, the same four scripts fire via
`sessionStart`/`beforeSubmitPrompt`/`preToolUse`/`stop`/`sessionEnd` through
`hooks/cursor-adapter.sh`; there is no Cursor equivalent of `Notification`,
so the permission/idle ping does not fire there.

Under Hermes, `pre_llm_call` records prompt start and injects abbreviations on
the first turn; `post_llm_call` supplies the final response directly to
`tg-on-stop.sh`; session finalize/reset cancels stale pending notices. Hermes
has no permission/idle hook, so that notice is intentionally omitted.

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
- in-repo paths use `AI_AGENTS_SKILLS_ROOT` with the runtime-specific
  `CLAUDE_PLUGIN_ROOT` / `PLUGIN_ROOT` / `CURSOR_PLUGIN_ROOT` fallbacks, never a
  hardcoded checkout path.

After moving a skill: commit + push → force a plugin update → verify the new
`gitCommitSha` (auto-update keys off the SHA, not the manifest `version`) → only
then delete the local duplicate from `~/.claude/skills/`. Host-/secret-/project-
specific material stays local.

## License

MIT — see [LICENSE](LICENSE).
