# schedule-tasks — internals & edge cases

## Byobu window name

Each fired job opens its own window in session `1`, named by `run-claude-task.sh` as
**`<2-letter project prefix>:<card ID>`**, hard-capped to **10 chars**:

- Card ID = leading `^[A-Za-z]+-[0-9]+` token (`K-025`, `FEAT-123`). Cards with no
  matching ID fall back to the first 7 chars of the filename.
- Examples: `avito-fix / K-025-serp-...` → `av:K-025`; `myproj / front-login-fix` → `my:front-l`.
- An unusually long ID is truncated tail-first to keep the 10-char cap.

Script source: `run-claude-task.sh` lines 35-37 (`CARD_ID` / `WIN_NAME`).

## Scripts in `${CLAUDE_PLUGIN_ROOT}/scripts/`

| Script                          | Role                                                       |
|---------------------------------|------------------------------------------------------------|
| `run-claude-task.sh`            | Outer: opens new tmux window in byobu session `1`, restarts a detached session if it died, `exec`s the inner script. Invoked by `at`. |
| `run-claude-task-inner.sh`      | Inner: runs INSIDE the spawned window. cd to repo, generate session-id (UUID), build the autonomous 4-commit prompt (start + impl(s) + review + ready), `claude --dangerously-skip-permissions --session-id … --debug-file …`, derive outcome from kanban stage (`ready/`=ok, `test/`/`progress/`=fail, `todo/`=skip), log usage stats, keep window open after exit. |
| `view-task-history.sh`          | Pretty-print any past run by session-id, task-name, or `--list`. |
| `summarize-task-usage.sh`       | Aggregate per-model token usage + approximate cost from the session JSONL; appends an "Auto-run usage" block to the task file. Called once at end of the inner run. |

**Scripts live in the immutable plugin cache** (`${CLAUDE_PLUGIN_ROOT}/scripts/`)
— they are not copied into, or tracked by, the target repo. Historical lesson
that shaped the design: an earlier autonomous prompt did `git stash -u` and
*vanished* in-repo untracked scripts mid-run. The current prompt refuses on
any dirty tree (step 1) and never stashes; with scripts out of the repo
entirely the failure mode is gone.

## Derived variables (in every script)

`SCRIPT_DIR` (own location) only locates **sibling scripts** in the plugin cache
— it is NOT used to find the target repo. The repo is derived **from the
task-file argument**: a card always lives at
`<repo>/.claude/kanban/<stage>/<name>.md`, so the repo is three levels up from
the card's directory. This makes the scripts location-independent. **No
project-specific constants to edit.**

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # plugin cache scripts/
TASK_FILE="$1"                                               # <repo>/.claude/kanban/<stage>/x.md
PROJECT_DIR="$(cd "$(dirname "$TASK_FILE")/../../.." && pwd)" # absolute repo root
PROJECT_NAME="$(basename "$PROJECT_DIR")"                     # e.g. myproject
CLAUDE_PROJECT_PATH="$(printf '%s' "$PROJECT_DIR" | tr '/' '-')"
                                                             # e.g. -home-user-myproject
```

`CLAUDE_PROJECT_PATH` is Claude Code's on-disk encoding of an absolute project
path under `~/.claude/projects/` (every `/` → `-`). Used to find the per-run
session JSONL.

Use the same derivation in ad-hoc shell snippets for this skill — the
SKILL.md examples assume `REPO=$(git rev-parse --show-toplevel)`.

## Session id, JSONL, debug log

The inner script generates a UUID `SESSION_ID` and passes it to claude as
`--session-id`. Two outputs result:

- `$LOG_DIR/<TS>_<task>.meta.log` — start/end markers, session id, resume hint, usage summary
- `$LOG_DIR/<TS>_<task>.debug.log` — claude's `--debug-file` output
- `~/.claude/projects/$CLAUDE_PROJECT_PATH/<SESSION_ID>.jsonl` — every prompt, tool call, and tool result (Claude Code writes this regardless)

Where:
```
LOG_DIR=$HOME/.local/state/claude-auto-runs/$PROJECT_NAME/
```

**Logs MUST live OUTSIDE the repo.** Historical bug: the debug log was inside
`.claude/kanban/_auto-runs/` and an early prompt that did `git stash -u`
stashed the open file mid-write → `appendFileSync` to a vanished file →
claude crashed with `ENOENT`. Mitigated by (a) log dir outside repo and
(b) refuse-on-dirty contract that never stashes.

## Inspecting past runs

```bash
# List recent auto-runs
"${CLAUDE_PLUGIN_ROOT}/scripts/view-task-history.sh" --list

# Pretty-print by session id
"${CLAUDE_PLUGIN_ROOT}/scripts/view-task-history.sh" <session-id>

# Or by (partial) task name — picks most recent match
"${CLAUDE_PLUGIN_ROOT}/scripts/view-task-history.sh" <task-name-fragment>

# Resume an interactive session in the original cwd
cd "$(git rev-parse --show-toplevel)"
claude --resume <session-id>
```

The end-of-run marker is always in `meta.log` and the window:
```
AUTO-RUN-RESULT: <ok|fail|skip>: <task>: <reason>
```

Cross-run summary:
```bash
grep -h '^AUTO-RUN-RESULT' "$HOME/.local/state/claude-auto-runs/$(basename "$(git rev-parse --show-toplevel)")"/*.meta.log
```

## How the chain actually works

1. **Refuse on dirty (prompt step 1).** `git status --porcelain`; if ANY
   modification (M/A/D/R/??) is present — sends tg-notify (s=warn, title
   `auto-run <NAME>: skip (dirty tree)`) then prints exactly
   `AUTO-RUN-RESULT: skip: <NAME>: working tree dirty, manual intervention required`
   and exits immediately. There is no auto-commit of WIP; the tree must be clean.
2. **Chain step (in the prompt, on `ok` only)** — the agent itself picks the
   next card per `lifecycle.md` rules and runs:
   ```bash
   echo "<SCRIPT_DIR>/run-claude-task.sh <REPO>/.claude/kanban/todo/<NEXT>.md" \
     | at -t $(date -d '+20 min' +%Y%m%d%H%M)
   ```
   Absolute paths are pre-interpolated into the prompt from `${SCRIPT_DIR}` /
   `${REPO}`; the agent must not substitute `$(pwd)`. "`ok`" is defined as
   "card landed in `ready/`".
3. **Final marker (last step of the prompt)** is non-negotiable: the very
   last output line is exactly
   `AUTO-RUN-RESULT: <ok|fail|skip>: <ID>: <reason>` (no markdown / quotes /
   trailing text). Emitted *after* the chain step by user requirement.
4. **The inner script never enqueues.** It only:
   - parses `AUTO-RUN-RESULT` from the JSONL (or falls back to the kanban stage when the marker is missing — see `lifecycle.md`);
   - looks for an `AUTO-RUN-NEXT: <basename>.md|none` marker in the JSONL and matches it against `atq` to verify the agent's `at` job actually landed;
   - emits loud `[inner] WARN:` lines in `meta.log` and the window when `result=ok` AND next card declared but no at-job queued. It does NOT auto-reschedule (would risk double-runs);
   - cleans up `.chain-conditions` as safety net when `AUTO-RUN-NEXT: none`.
5. **+20 min gap.** Scheduling buffer between consecutive runs — gives the previous interactive claude window time to be closed/idle and any post-exit housekeeping to settle before the next run fires. The window itself is NOT auto-closed — the agent enqueues the next `at` BEFORE the final `AUTO-RUN-RESULT` marker (step 9 of the prompt), so the chain advances even if the user never closes the previous window.

## Escalation & tg-notify

The autonomous run is **not** fully silent. It decides on its own by default, but stops and asks
the user in exactly **two** cases:

- **Blocker** it cannot safely resolve autonomously: missing access/creds, unresolvable conflict,
  destructive operation, or an ambiguity where a wrong pick is costly to undo.
- **Architecture/logic-changing decision**: API contract, DB schema, public behaviour, or a choice
  between materially different approaches.

Everything else (minor ambiguity, style, local impl detail) the agent resolves itself and proceeds.

**Escalation sequence (prompt-enforced order):**
1. Send **tg-notify** first (`tg-notify` skill, main thread only — subagents never notify). Message
   must be self-contained: task name, the question/decision, what the agent will pick by default,
   AND how to reach the session (`byobu attach` → session `1`, or `claude --resume <SESSION_ID>`).
2. Block on `AskUserQuestion` — window blocks, next `at` job is NOT armed until answered.
3. On answer: log decision in card's Execution Log (arch decisions also go in **Decisions** section)
   then continue.

**When tg-notify fires (main thread only):**
- On escalation — before blocking.
- On terminal `fail` (qa-check or review red) — before the final marker.
- On terminal `skip` (dirty tree at step 1) — before exit.
- NOT on `ok` (chain self-advances; long runs already covered by tg-notify auto-hooks).
- NOT on the benign "not in todo" skip.

**Soft dependency:** if `TELEGRAM_BOT_TOKEN`/`TELEGRAM_CHAT_ID` are not configured the agent
still asks in the window — the user just won't be pinged.

## Conditions propagation (`.chain-conditions`)

User-supplied constraints (set by the `/schedule-tasks` orchestrator in
step 3) live in a single file:

```
$LOG_DIR/.chain-conditions
  = $HOME/.local/state/claude-auto-runs/$PROJECT_NAME/.chain-conditions
```

Every chained inner-script invocation is **intended** to read this file at startup and embed
its contents verbatim into the autonomous prompt under a "Дополнительные условия пользователя"
block. Examples: "не пушить", "use sonnet", "после каждой задачи прогон e2e", "только front-*
карточки", branch overrides, etc.

> ⚠ **Not yet wired in `run-claude-task-inner.sh`** — the file injection into the prompt is
> planned but currently not implemented. The orchestrator step still writes the file, but the
> inner script does not yet read it. Check the script before relying on this feature.

Lifecycle (design intent):
- Created/overwritten by orchestrator (SKILL.md step 3) before the first at-job fires.
- To be read by every chain link at startup and injected into the prompt.
- To be deleted by the agent at step 9 when `AUTO-RUN-NEXT: none` (chain ended cleanly).
- Safety net: inner script also deletes the file if the agent skips cleanup.

Empty file = no extra conditions; no block injected into the prompt.

## Edge cases / risks

- **Refuse-on-dirty cascading** — if task N fails (qa or review) and leaves the tree dirty, task N+1 SKIPs. Intentional. Surface this in the post-run summary so the user knows to clean up.
- **Card stuck in `progress/` or `test/`** — the autonomous run never auto-reopens a failed card. The next at-job for that card needs the user to fix and rerun manually, or move it back to `todo/` explicitly.
- **Run blocked on an escalation question** — the prompt lets the agent stop and ask the user on a blocker or an arch/logic-changing decision (see SKILL.md → *Escalation & Telegram notifications*). It fires a `tg-notify` ping **first**, then blocks on `AskUserQuestion` in the open window. While blocked it never reaches step 9, so the chain's next `at` job is **not** armed — the autopilot pauses until the user answers (via `byobu attach` or `claude --resume <SESSION_ID>`). Key risk: this relies on `AskUserQuestion` rendering/blocking correctly under `--dangerously-skip-permissions` (it should — skip-permissions bypasses permission prompts, not the question UI; the run launches interactive, not `-p` headless).
- **`tg-notify` not configured** — escalation/fail/skip pings silently no-op (or print a sender error in the window); the run itself is unaffected — the agent still asks in the window and still emits `AUTO-RUN-RESULT`. The user just isn't pinged.
- **Long task overruns its slot** — slot is just `at` firing time; nothing kills the previous claude. Two windows can run in parallel. The second window's step-1 dirty-tree check will see uncommitted state from the first and SKIP immediately (tg-notify sent). Warn the user when scheduling heavy cards close together (<60 min apart).
- **Byobu session killed** — outer script auto-creates a detached session `1`; user reattaches with `byobu attach` to see the window.
- **`cron` vs. `at`** — never use cron for one-shot; it leaves a recurring entry unless self-removed. `at` is the right primitive.
- **Permissions** — `--dangerously-skip-permissions` skips ALL approvals; only use for scheduled autonomous runs the user explicitly requested.
- **Self-chain runaway** — a chain only advances on `ok`; the agent arms exactly one `at` job (+20 min) for the single next card, so at most one chained job is ever queued. `fail`/`skip` (or dirty tree at step 9) breaks the chain rather than looping.
- **Agent skipped the `at` call** — chain silently stops. Mitigated: step 9 of the prompt tells the agent to verify `at` printed a job id; the inner script emits a loud `[inner] WARN: result=ok but no at-job queued` in meta.log + the window. It does NOT auto-reschedule (no double-run risk).
- **Manual batches + self-chain coexist** — they CAN both be active, but you'll get double-booked windows. Pick one mode or the other.
- **`.chain-conditions` orphan after `fail`/`skip`** — cleanup only fires on `AUTO-RUN-NEXT: none` (clean chain end). On `fail`/`skip` the file persists. The next `/schedule-tasks` orchestrator overwrites it, so users running through the orchestrator are fine. But if the user re-arms a single card with raw `at` (skipping `/schedule-tasks`), they silently inherit stale conditions from the previous failed chain. Workaround: `rm $HOME/.local/state/claude-auto-runs/$(basename "$(git rev-parse --show-toplevel)")/.chain-conditions` before manual at-jobs.

## Project-agnostic guarantees

The skill is portable across repos because:

- **Scripts derive the repo from the task-file argument** — no env vars or constants to edit per repo; the scripts themselves live in the plugin cache.
- **The prompt names no project-specific agents or skills.** It tells the agent to inspect the host project's `CLAUDE.md` for subagent routing and lint/test commands; if none documented, the agent uses targeted commands for the touched files.
- **No allow/deny lists, no roadmap parsing.** Next-card selection is the related-then-lex rule in `lifecycle.md`.
- **The inner script's outcome detection** uses `AUTO-RUN-RESULT` + kanban-stage fallback — both work in any project that uses the standard `.claude/kanban/{todo,progress,test,done}/` layout.

Install this plugin and run `/schedule-tasks` from any repo — it works as-is,
provided `.claude/kanban/todo/` exists and `atd` is running.
