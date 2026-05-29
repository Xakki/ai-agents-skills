# schedule-tasks — internals & edge cases

## Scripts in `${CLAUDE_PLUGIN_ROOT}/scripts/`

| Script                          | Role                                                       |
|---------------------------------|------------------------------------------------------------|
| `run-claude-task.sh`            | Outer: opens new tmux window in byobu session `1`, restarts a detached session if it died, `exec`s the inner script. Invoked by `at`. |
| `run-claude-task-inner.sh`      | Inner: runs INSIDE the spawned window. cd to repo, generate session-id (UUID), build the autonomous 2-commit prompt (impl + review), `claude --dangerously-skip-permissions --session-id … --debug-file …`, derive outcome from kanban stage (`ready/`=ok, `test/`/`progress/`=fail, `todo/`=skip), log usage stats, keep window open after exit. |
| `view-task-history.sh`          | Pretty-print any past run by session-id, task-name, or `--list`. |
| `summarize-task-usage.sh`       | Aggregate per-model token usage + approximate cost from the session JSONL; appends an "Auto-run usage" block to the task file. Called once at end of the inner run. |

**Scripts live in the immutable plugin cache** (`${CLAUDE_PLUGIN_ROOT}/scripts/`)
— they are not copied into, or tracked by, the target repo. Historical lesson
that shaped the design: an earlier autonomous prompt did `git stash -u` and
*vanished* in-repo untracked scripts mid-run. The current prompt no longer
stashes (it auto-commits pending WIP at step 1), and with scripts out of the
repo entirely the failure mode is gone.

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
PROJECT_NAME="$(basename "$PROJECT_DIR")"                     # e.g. unidoski
CLAUDE_PROJECT_PATH="$(printf '%s' "$PROJECT_DIR" | tr '/' '-')"
                                                             # e.g. -home-xakki-unidoski
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
(b) auto-commit-at-step-1 contract that never stashes.

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

1. **Auto-commit pending WIP (prompt step 1).** Never refuses on dirty;
   commits everything to `wip: pre-task auto-commit before <ID>` first. Hard
   skip only if an obviously sensitive untracked file (`secrets.yml`,
   `dump.sql`, `*.pem`, `id_rsa`) appears outside `.gitignore`.
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
5. **+20 min gap.** Gives the previous interactive claude window time to be closed/idle and any post-exit housekeeping to settle before the next run's auto-commit step picks up leftovers. The window itself is NOT auto-closed — the agent enqueues the next `at` BEFORE the final `AUTO-RUN-RESULT` marker (step 9 of the prompt), so the chain advances even if the user never closes the previous window.

## Conditions propagation (`.chain-conditions`)

User-supplied constraints (set by the `/schedule-tasks` orchestrator in
step 3) live in a single file:

```
$LOG_DIR/.chain-conditions
  = $HOME/.local/state/claude-auto-runs/$PROJECT_NAME/.chain-conditions
```

Every chained inner-script invocation reads this file at startup and embeds
its contents verbatim into the autonomous prompt under a "Дополнительные
условия пользователя" block, marked as applying to **this and all subsequent
links**. Examples of conditions: "не пушить", "use sonnet", "после каждой
задачи прогон e2e", "только front-* карточки", branch overrides, etc.

Lifecycle:
- Created/overwritten by orchestrator (SKILL.md step 3).
- Read by every chain link at startup.
- Deleted by the agent at step 9 when `AUTO-RUN-NEXT: none` (chain ended).
- Safety net: inner script also deletes the file if the agent forgot.

Empty file = no extra conditions; no block injected into the prompt.

## Edge cases / risks

- **Refuse-on-dirty cascading** — if task N fails (qa or review) and leaves the tree dirty, task N+1 SKIPs. Intentional. Surface this in the post-run summary so the user knows to clean up.
- **Card stuck in `progress/` or `test/`** — the autonomous run never auto-reopens a failed card. The next at-job for that card needs the user to fix and rerun manually, or move it back to `todo/` explicitly.
- **Long task overruns its slot** — slot is just `at` firing time; nothing kills the previous claude. Two windows can run in parallel. Both will auto-commit pending state at step 1 → second window may bundle the first's partial work into its own `wip:` commit. Warn the user when scheduling heavy cards close together (<60 min apart).
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
