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
plugin (`plugin.yaml` + `__init__.py`) — see [Install (Hermes)](#install-hermes) —
and a [Prime Agent package](#install-prime-agent). All five integrations share
the same `skills/` tree; see
[AGENTS.md](AGENTS.md) for the repo conventions that keep them in sync.

## Skills

Skill names follow `<area>-<object>-<goal>`: the **area** (first part) says where the skill applies, the **object** narrows it, and the **goal** says what the skill achieves. Areas and goals come from the closed lists in [skills-registry.json](skills-registry.json), enforced by `python3 scripts/skills_registry.py check`.

**Loading.** The `always` list in [skills-registry.json](skills-registry.json) defines the skills that permit automatic model invocation in Claude Code and Codex. The other skills require the user to invoke them manually (`/ai-agents-skills:<name>` in Claude Code, `$<name>` in Codex). The [catalog](skills/agent-skill-find/references/catalog.md) marks the automatic tier with `*` and helps the agent suggest a manual invocation. Do not read a hidden skill's `SKILL.md` to reproduce a blocked invocation; supporting files of an invoked skill remain usable as its dependencies, subject to runtime permissions. Claude normally includes only permitted skill descriptions in the model context and loads full instructions when invoked; actual discovery and context cost depend on the runtime and its settings. Other integrations may interpret the metadata differently. Run `python3 scripts/skills_registry.py apply` after changing the list to update shared Claude frontmatter, Codex metadata and the catalog. These settings do not override native refusals or authorize side effects.

### agent

Agents themselves: skills, context, models, hooks, mcp, delegation, notifications.

| Skill | What it does |
|---|---|
| **agent-command-run** | Run a noisy command and report compact output without losing failure evidence or confusing process outcomes. |
| **agent-context-audit** | Assess agent context and agent-skill-find budgets using the real runtime interfaces. |
| **agent-hook-verify** | Verify agent hook registration and behavior with safe allow/block cases. |
| **agent-integration-audit** | Audit agent plugin, skill, hook and MCP integration across runtime boundaries. |
| **agent-model-find** | Resolve optional model-tier settings through the active agent runtime. |
| **agent-project-sync** | Resolve project identity or synchronize an installed asset using the runtime's authorized interfaces. |
| **agent-skill-find** | Find, compare and select agent skills for a task, preserving source, permissions and installation boundaries; includes the catalog of this plugin's skills. |
| **agent-skill-sync** | Discover reviewed skills in configured Git sources and safely import or update a selected skill. |
| **agent-telegram-notify** | Send an authorized Telegram notification or task/completion report to a configured chat or topic, and tune the notification hook timers. |
| **agent-terms-define** | Authoritative dictionary of standard developer abbreviations for variables, functions, classes, CSS classes and terse technical writing, injected at session start. |
| **agent-workspace-migrate** | Plan or perform authorized migration of agent skills, instructions, hooks and configuration across consumers. |

### api

Api contracts, protocols, api documentation, external provider and oauth integrations.

| Skill | What it does |
|---|---|
| **api-contract-define** | Implement, repair or independently review API operations and cross-layer contracts, tracing producer to consumer wire behavior end to end. |
| **api-docs-sync** | Reconcile API documentation, OpenAPI artifacts, documentation UIs and public capability catalogs (llms.txt, indexes) with the shipped implementation. |
| **api-stream-diagnose** | Debug and verify streamed parsers, framing, terminal state and continuation requests. |
| **api-yandex-oauth-run** | Research Yandex OAuth token flows, exchange or refresh tokens and diagnose authorization through approved interfaces. |

### code

Writing and restructuring source code: cli, configuration, concurrency, durable state, performance.

| Skill | What it does |
|---|---|
| **code-async-review** | Design or review deadlines, cancellation, ownership handoffs and asynchronous lifecycles with tests. |
| **code-cli-build** | Implement or review command-line behavior: parsing, output, state, operator actions and subprocess results. |
| **code-config-audit** | Trace configuration, defaults, generated catalogs, startup wiring and readiness across services and environments. |
| **code-durable-review** | Design or review durable jobs, leases, replay, recovery and ordered external effects. |
| **code-performance-fix** | Measure and improve performance (web vitals, benchmarks, data access) using representative workloads and raw-sample evidence. |
| **code-state-verify** | Validate persisted and in-memory state transitions, schemas, counters and authorization snapshots. |

### deploy

Rollouts, releases, cutovers, publishing.

| Skill | What it does |
|---|---|
| **deploy-artifact-publish** | Publish a self-contained HTML artifact or page to a self-hosted static site via the project make target and return its public URL. Use when asked to publish a page. |
| **deploy-rollout-run** | Plan, perform or verify authorized rollouts, cutovers and releases with scoped evidence and rollback. |

### design

Brand identity, graphics, visual design.

| Skill | What it does |
|---|---|
| **design-brand-build** | Develop or review a brand identity, name, guidelines or approved visual asset family. |

### docs

Documentation, diagrams, documents, prose.

| Skill | What it does |
|---|---|
| **docs-claims-verify** | Review or correct documentation claims against the authoritative implementation and dated evidence. |
| **docs-diagram-build** | Design a legible architecture, deployment, infrastructure or data-flow diagram from the bundled template. |
| **docs-prose-fix** | Edit text for natural, precise prose while preserving meaning and voice. |

### git

Version control: commits, branches, merges, worktrees, pull requests.

| Skill | What it does |
|---|---|
| **git-branch-clean** | Audit, archive, rename or delete Git branches without losing work, with plan-hash-bound cleanup helpers. |
| **git-merge-sync** | Reconcile merges and divergent histories while keeping both sides' behavior and a recoverable source state. |
| **git-path-run** | Move or remove project paths while preserving Git history and local work, via the git-aware helper. |
| **git-repo-run** | Perform scoped Git work safely: inspect, stage, commit, branch, push, prepare a pull request. |
| **git-worktree-guard** | Preserve other actors' staged, unstaged and untracked work in a shared checkout. |

### infra

Hosts, vms, containers, networking, storage, project migration, runbooks.

| Skill | What it does |
|---|---|
| **infra-container-setup** | Scaffold a project with containers when containerization is requested or required. |
| **infra-network-diagnose** | Diagnose endpoint connectivity and proxy routing across the actual network boundaries. |
| **infra-project-migrate** | Plan and verify an authorized migration of a named project, its services or data between hosts or runtimes. |
| **infra-runbook-build** | Create evidence-based runbooks for operational tasks using supported project interfaces. |

### kanban

Task boards: cards, epics, grooming, queues, schedules, roadmaps.

| Skill | What it does |
|---|---|
| **kanban-board-audit** | Audit Kanban cards for duplicate, completed, blocked and epic-ready work, and repair or reorganize a board while preserving scope and stages. |
| **kanban-card-build** | Deliver an authorized Kanban queue autonomously while preserving scope and evidence, including measurement-backed cards. |
| **kanban-card-plan** | Groom a request or draft card into implementation-ready, measurable, dependency-safe cards and validate the grooming. |
| **kanban-card-review** | Read-only review of a card lifecycle or a proposed promotion against history, dependencies and evidence, returning APPROVE or REQUEST CHANGES. Use for independent.... |
| **kanban-card-run** | Operate the project Kanban board: create, groom, start, move, review and complete cards through the board helpers, with owner decisions and lifecycle rules. |
| **kanban-card-verify** | Record and verify acceptance evidence on a Kanban card, hand off an implemented child, verify lifecycle moves and keep helper effects, evidence and Git scope separate. |
| **kanban-epic-coordinate** | Plan, govern and deliver one approved Kanban epic: scoped execution, dependencies, pauses, review, integration and authorized handoff. |
| **kanban-queue-coordinate** | Coordinate authorized autonomous execution of a project plan or queue with gates, independent review and checkpoints; delegation follows the superpowers subagent skills. |
| **kanban-roadmap-plan** | Plan, track or execute a phased product roadmap. |
| **kanban-schedule-run** | Plan or run explicitly authorized scheduled work on selected Kanban cards. |

### monitor

Logs, metrics, tracing, dashboards, alerts.

| Skill | What it does |
|---|---|
| **monitor-telemetry-setup** | Design, configure or diagnose telemetry delivery, structured logging (Fluent Bit), storage and dashboards from observable runtime evidence. |

### personal

Notes, reminders, mail, calendar, career and household tasks.

| Skill | What it does |
|---|---|
| **personal-action-plan** | Extract traceable decisions and proposed actions from documents or meeting notes. |
| **personal-resume-build** | Populate career forms from a resume and verified experience without inventing qualifications. |

### quality

Review, acceptance, validation and risk of delivered work.

| Skill | What it does |
|---|---|
| **quality-artifact-verify** | Review build and release artifacts, images and versioned deliverables against their actual inputs, packaging and runtime contracts. |
| **quality-change-review** | Independently review or accept a candidate change and verify defect claims with evidence, separating findings, gaps and hypotheses. |
| **quality-change-verify** | Run and report a final, post-repair or pre-completion validation pass with exact commands, exit codes and limits, discovering the project's sanctioned checks. |
| **quality-risk-triage** | Assess observed and speculative technical risks, ownership and evidence before choosing mitigation or deferral. |

### research

Sources, citations, prior art, knowledge bases.

| Skill | What it does |
|---|---|
| **research-claims-verify** | Ground externally sourced claims in direct, verifiable citations with explicit evidence limits. |
| **research-knowledge-build** | Build a provenance-backed knowledge base from authorized training media and transcripts. |
| **research-prior-art-find** | Find and compare existing implementations before designing or changing software. |
| **research-source-audit** | Monitor requested sources or subjects for material changes using supported interfaces. |
| **research-source-find** | Research documented API or data-source contracts, cite evidence, and recover permitted alternative sources when a source is inaccessible. |
| **research-spike-run** | Run a scoped feasibility experiment and report evidence before committing to an implementation. |

### security

Boundaries, authorization, secrets, privacy, hardening.

| Skill | What it does |
|---|---|
| **security-access-diagnose** | Diagnose an access refusal while preserving native approval and security boundaries. |
| **security-api-harden** | Secure or review API ingress, transport, identity and response failure boundaries, plus resource, tenant and workspace authorization. |
| **security-boundary-harden** | Harden a scoped security boundary while preserving behavior and verifying the actual controls. |
| **security-boundary-review** | Independently review a claimed security repair or boundary contract with adversarial tests and current evidence, read-only. |
| **security-filesystem-harden** | Secure filesystem artifacts, bounded reads and lifecycle state against replacement races. |
| **security-ipc-verify** | Validate peer authority, framing and fail-closed broker IPC boundaries. |
| **security-outbound-guard** | Bound external attempts and validate outbound work across retries and background paths. |
| **security-privacy-review** | Review secret handling, redaction, no-read and privacy claims across application boundaries. |

### test

Testing strategy, harnesses, coverage, evaluation.

| Skill | What it does |
|---|---|
| **test-coverage-audit** | Inventory tests and coverage gaps from evidence without implying permission to change or run them. |
| **test-harness-verify** | Verify that a test runner, fixture, isolated runtime or generated artifact really ran what it claims, at the consumer boundary. |
| **test-llm-scenario-run** | Design and run bounded, reproducible scenario evaluations for LLM applications. |

## Agents

| Agent | What it does |
|-------|--------------|
| **ai-agents-skills:log-investigator** | Read-only incident triage. Pulls container logs (Portainer), app logs (Graylog), and metrics (Grafana/Prometheus) and returns a focused UTC timeline + likely root cause — not a raw log dump. `model:` frontmatter = plugin **standard**-tier default (`sonnet`); override via `AI_MODEL_*` / skill `agent-model-find`. Mutations denied. On first use in a project it **asks** for the service/tag/endpoint context and offers to save it to your `.claude/`. |
| **ai-agents-skills:db-schema** | Read-only DB schema introspection. Returns concise `table → columns → PK → indexes → FKs` summaries from the live DB, migrations, or config — always naming the source. `model:` frontmatter = plugin **standard**-tier default (`sonnet`); override via `AI_MODEL_*` / skill `agent-model-find`. Mutations/migrations denied. Asks for ORM/stack/paths on first use. |

Claude and Cursor auto-discover agents from `agents/` and address them as
`ai-agents-skills:<name>`. The Codex package exposes the shared `skills/` tree;
The root `agents/` prompts are not declared by its Codex manifest.
Hermes exposes the same prompt bodies as read-only
plugin skills named `ai-agents-skills:agent-<name>` (for example,
`skill_view("ai-agents-skills:agent-log-investigator")`).

## Install (Claude Code)

As a marketplace from this repo:

```
/plugin marketplace add Xakki/ai-agents-skills
/plugin install ai-agents-skills@ai-agents-skills
```

### Dependency: superpowers

This plugin also declares a dependency on the [superpowers](https://github.com/obra/superpowers)
plugin from the official marketplace (`claude-plugins-official`, allowed through
`allowCrossMarketplaceDependenciesOn`). Installing `ai-agents-skills` installs it too, and all of its
skills stay auto-loaded exactly as superpowers ships them (its `SessionStart` hook injects
`using-superpowers`). If the official marketplace is not added in your Claude Code, add it before
installing. Skills in this plugin that duplicated superpowers (debugging,
test-driven development, completion verification, delegation) were removed on purpose.

Codex has no documented plugin-dependency mechanism: install superpowers separately
(`/plugins`, search `superpowers`, Install Plugin) and confirm with `/skills` that both plugins' skills
are listed. Cursor, Hermes and Prime are not covered by an automatic dependency.

MemPalace is not required by this plugin. If you need it, install and configure
it separately under its own authorization and data-retention policy.

Or from a local checkout:

```
/plugin marketplace add /path/to/ai-agents-skills
/plugin install ai-agents-skills@ai-agents-skills
```

Verify the manifest and skill frontmatter at any time:

```
claude plugin validate /path/to/ai-agents-skills
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
notifications configured by `agent-telegram-notify`; review the outbound commands before
trusting them. Root `agents/` prompts remain available to the Claude, Cursor,
and Hermes integrations only.

### Verify the Codex install

```
codex plugin marketplace list   # confirms the GitHub marketplace is registered
codex plugin list               # lists ai-agents-skills in its marketplace snapshot
```

MemPalace is optional and must be installed separately if needed.

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
slash-command registrations: use `skill_view("ai-agents-skills:kanban-card-run")` when you want the workflow. The
built-in `/kanban` board command remains separate. All `agents/*.md` prompts
remain namespaced as `ai-agents-skills:agent-<name>`. You can also load skills
explicitly, for example:

```text
skill_view("ai-agents-skills:kanban-card-run")
skill_view("ai-agents-skills:quality-change-verify")
skill_view("ai-agents-skills:kanban-epic-coordinate")
skill_view("ai-agents-skills:agent-db-schema")
```

The Hermes adapter maps `pre_llm_call`, `post_llm_call`, session-finalize, and
session-reset events to the shared abbreviation and Telegram hook behavior.
Hermes does not expose a plugin hook for permission/idle notifications, so that
specific Telegram ping is not wired. Setting
`plugins.entries.ai-agents-skills.settings.telegram_hooks: false` in the Hermes
config turns the Telegram hooks off for Hermes only (absent = on); the
abbreviation context is still injected. `kanban-schedule-run` remains a
Claude-specific workflow; `agent-model-find` is informational under Hermes because
Hermes subagents inherit the active model rather than accepting a per-call tier.
MemPalace is optional and is not installed by this plugin.

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

MemPalace is optional and must be installed separately if needed.

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
├── skills/                # one level only: <area>-<object>-<goal>/SKILL.md (+ references/, scripts/, agents/openai.yaml)
├── skills-registry.json   # closed lists of areas and goals
├── statusline/            # opt-in status-line renderers (see statusline/README.md)
│   ├── statusline-command.sh
│   └── subagent-statusline-command.sh
└── scripts/               # runners used by kanban-schedule-run, skills_registry.py (naming lint, tiers, catalog)
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

## Usage

- **kanban** triggers on task-management requests ("create a task", "what's in
  progress", "mark done"). It operates on `.claude/kanban/` in your *current*
  project; the board is created on first use.
- **kanban-schedule-run** triggers on "schedule tasks" / "запланируй задачи". It needs
  `atd` active and a byobu/tmux session, and reads cards from
  `.claude/kanban/todo/` in your current project.
- **agent-telegram-notify** triggers on "send to telegram" / "notify in TG" / "ping me when
  done", and auto-sends via its hooks for long task completion and
  permission/idle prompts. See [agent-telegram-notify](#agent-telegram-notify) for setup.

### kanban-schedule-run & the plugin cache

`kanban-schedule-run` invokes the runner scripts from `${CLAUDE_PLUGIN_ROOT}/scripts/`
(the installed plugin's cache), not from your repo. The scripts derive the
target repo from the task-file path they're given
(`<repo>/.claude/kanban/<stage>/<name>.md`), so they work from any project
without per-repo configuration. Your kanban board still lives in your project
under `.claude/kanban/`.

### agent-telegram-notify

The bot token and destination come from the **environment** — nothing secret is
committed. Configure once, then both the manual sender and the hooks use it.

1. Create a bot with [@BotFather](https://t.me/BotFather) and copy its token.
2. Copy the template and fill it in (chmod 600):

   ```
   mkdir -p ~/.config/tg-notify
   ROOT="${AI_AGENTS_SKILLS_ROOT:-${CLAUDE_PLUGIN_ROOT:-${PLUGIN_ROOT:-${CURSOR_PLUGIN_ROOT:-}}}}"
   cp "$ROOT/skills/agent-telegram-notify/.env.example" ~/.config/tg-notify/.env
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

`agent-telegram-notify` (and its hooks) use **`TELEGRAM_CHAT_ID`** — typically your **DM**, so
"task finished / needs attention" pings reach you privately. The **`agent-telegram-notify`**
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
creds file. If `agent-telegram-notify` finds a required value unset, it **asks** rather than
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

- `kanban-schedule-run`: `atd` running (`systemctl is-active atd`), `at`/`atq`/`atrm`,
  a tmux/byobu session, and `claude` on `PATH`.
- `agent-telegram-notify`: `curl`, `jq`, `python3`, and (for the context header in hooks) a
  tmux/byobu session. A `TELEGRAM_BOT_TOKEN` + `TELEGRAM_CHAT_ID` as above.

## Recommendation skills

- impeccable (for landings) `npx -y skills add pbakaus/impeccable --skill impeccable --agent claude-code -g`
- task observer `npx -y skills add rebelytics/one-skill-to-rule-them-all --skill task-observer --agent claude-code -g`

## Contributing — when to migrate a skill here

A debugged, **universal** skill / agent / rule belongs in this plugin. Criteria:
it works correctly **and** carries no personal data. Parameterize it via env/config
following the `agent-telegram-notify` pattern:

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
