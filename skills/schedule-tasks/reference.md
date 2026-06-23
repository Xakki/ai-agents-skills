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
| `run-claude-task-inner.sh`      | Inner: runs INSIDE the spawned window. Captures baseline dirty-set, builds autonomous prompt, runs `claude --dangerously-skip-permissions`, derives outcome, logs usage stats, verifies chain at-job. |
| `park-task.sh`                  | Deterministic park: ensure on `task/<NAME>` branch, stage extra paths (baseline-aware, no bulk-stage), commit `wip(park): <NAME> (<REASON>)`, switch back to base, write `.parked/<NAME>` index. Args: `<TASK_FILE> <BASE_BRANCH> <BASELINE_FILE> <SESSION_ID> <LOG_DIR> <REASON>`. REASON ∈ qa-fail\|review-fail\|blocker\|question\|merge-conflict. |
| `select-next-task.sh`           | Dependency-aware next-card selection: skip blocked cards (depend on a parked task), prefer related-first, else lex-smallest. Prints basename or `none`. Args: `<REPO> <PARKED_DIR> [<JUST_FINISHED_NAME>]`. |
| `view-task-history.sh`          | Pretty-print any past run by session-id, task-name, or `--list`. |
| `summarize-task-usage.sh`       | Aggregate per-model token usage + approximate cost from the session JSONL; appends an "Auto-run usage" block to the task file. Called once at end of the inner run. |

**Scripts live in the immutable plugin cache** (`${CLAUDE_PLUGIN_ROOT}/scripts/`)
— they are not copied into, or tracked by, the target repo. Historical lesson
that shaped the design: an earlier autonomous prompt did `git stash -u` and
*vanished* in-repo untracked scripts mid-run. The current prompt forbids
`git stash` and any bulk-staging; with scripts out of the repo entirely
the failure mode is gone.

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
- `$LOG_DIR/.baseline-dirty-<TS>` — `git status --porcelain` snapshot taken **before** claude runs. Read by (a) the chain bash block (step 9) via `comm -23` to detect only new uncommitted task changes, and (b) the end-of-run auto-commit block to identify new kanban `.md` paths to stage. Deleted at the very end of the inner script run. If the file is missing at chain step time, `sort` fails silently and the baseline is treated as empty (worst case: chain stops on pre-existing dirt — safe).

Where:
```
LOG_DIR=$HOME/.local/state/claude-auto-runs/$PROJECT_NAME/
```

**Logs MUST live OUTSIDE the repo.** Historical bug: the debug log was inside
`.claude/kanban/_auto-runs/` and an early prompt that did `git stash -u`
stashed the open file mid-write → `appendFileSync` to a vanished file →
claude crashed with `ENOENT`. Mitigated by (a) log dir outside repo and
(b) the prompt never stashing (`git stash` is forbidden).

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

1. **Dirty tree is fine (prompt step 1).** The tree may be dirty at run start —
   the agent proceeds normally. Pre-existing uncommitted files are never stashed,
   reset, or absorbed into the task's commits. Staging is always explicit-path
   (`git add <paths>`; never `git add -A`/`.`/`-u`/`-a`). The chain dirty-check
   (step 9) uses a baseline snapshot taken before the run (see "Session id, JSONL,
   debug log" for `BASELINE_FILE`) and stops the chain only when there are **new**
   uncommitted paths on base — pre-existing dirt is ignored.
2. **Per-task branch.** Step 3 commits `task: start` on base (removing the card from
   `todo/` so the chain won't re-pick it), then creates `task/<NAME>`. All impl,
   qa, and review commits land on the branch. On success (step 8), the agent merges
   `--no-ff` to base and deletes the branch. On any failure the agent calls
   `park-task.sh` which commits WIP on the branch and returns to base; the branch
   stays unmerged.
3. **Chain step (step 9, on ok/park/skip).** Step 9 runs on **every** outcome.
   The agent calls `select-next-task.sh` (pre-interpolated path) to find the next
   unblocked card, then enqueues it via `at -t +20min`. Blocked cards (depending on
   a parked task) are automatically skipped. `ok|park|skip` all advance the chain.
4. **Final marker (last step of the prompt)** is non-negotiable:
   `AUTO-RUN-RESULT: <ok|park|skip>: <ID>: <reason>` (no markdown / quotes / trailing text).
   Emitted *after* the chain step.
5. **The inner script never enqueues.** It only:
   - parses `AUTO-RUN-RESULT` from the JSONL (or falls back to the kanban stage when the marker is missing — see `lifecycle.md`);
   - looks for an `AUTO-RUN-NEXT: <basename>.md|none` marker in the JSONL and matches it against `atq` to verify the agent's `at` job actually landed;
   - emits loud `[inner] WARN:` / `[inner] ERROR:` lines in `meta.log` and the window when `result=ok|park|skip` AND next card declared but no at-job queued. It does NOT auto-reschedule (would risk double-runs);
   - cleans up `.chain-conditions` as safety net when `AUTO-RUN-NEXT: none`.
6. **+20 min gap.** Scheduling buffer between consecutive runs. The window is NOT auto-closed — the agent enqueues the next `at` BEFORE the final `AUTO-RUN-RESULT` marker (step 9), so the chain advances even if the user never closes the previous window.

## Escalation = park & advance (non-blocking)

The autonomous run decides on its own by default. In exactly **two** cases it cannot continue:

- **Blocker** it cannot safely resolve autonomously: missing access/creds, unresolvable conflict,
  destructive operation, or an ambiguity where a wrong pick is costly to undo.
- **Architecture/logic-changing decision**: API contract, DB schema, public behaviour, or a choice
  between materially different approaches.

Everything else (minor ambiguity, style, local impl detail) the agent resolves itself and proceeds.
`AskUserQuestion` is **never** used — the run is always non-blocking.

**Park sequence (prompt-enforced order):**
1. If on base (merge-conflict only): `git switch "task/<NAME>"` to get to the branch.
2. Annotate the card at its current stage (progress/|test/|ready/) with
   `## ⏸ Parked — <REASON>`: branch name, description of problem, proposed options/default.
3. Call `park-task.sh "<card-path>" "<BASE_BRANCH>" "<BASELINE_FILE>" "<SESSION_ID>" "<LOG_DIR>" <REASON>` —
   the script stages extra paths (baseline-aware, no bulk-stage), commits
   `wip(park): <NAME> (<REASON>)`, switches back to base, writes the `.parked/<NAME>` index.
4. Send **tg-notify** (main thread only): task name, branch `task/<NAME>`, problem summary,
   proposed options/default, how to resume (`/schedule-tasks resume <NAME>` or
   `claude --resume <SESSION_ID>`).
5. Run **chain step 9** (select-next-task.sh picks next unblocked card at +20 min).
6. Emit `AUTO-RUN-RESULT: park: <NAME>: parked (<REASON>)` as the final marker.

**When tg-notify fires (main thread only):**
- On `park` (step 6 above) — after branch/commit, before final marker.
- NOT on `ok` (chain self-advances; long runs already covered by tg-notify auto-hooks).
- NOT on `skip` (benign "not in todo" or no eligible card).

**Soft dependency:** if `TELEGRAM_BOT_TOKEN`/`TELEGRAM_CHAT_ID` are not configured the tg-notify
step silently no-ops; the run still parks, chains, and emits its final marker normally.

## Parked state index (`.parked/`)

File: `$HOME/.local/state/claude-auto-runs/<PROJECT>/.parked/<TASK_NAME>`

Created by `park-task.sh`. Content:
```
branch=task/<TASK_NAME>
base=<BASE_BRANCH>
session=<SESSION_ID>
reason=<REASON>
card=<relative card path, e.g. .claude/kanban/progress/<TASK_NAME>.md>
```

`questions` / open-question detail lives in the `## ⏸ Parked — <REASON>` section
of the card itself (the agent writes it before calling `park-task.sh`).

Lifecycle:
- **Created**: by `park-task.sh` (called at prompt park step 3, before tg-notify at step 4).
- **Read**: by `/schedule-tasks resume` to discover parked tasks and reconstruct context.
- **Deleted**: when the resumed task lands in `ready/` (resume cleanup step).
- **Persists on fail/skip**: if the resumed task fails qa or review, the `.parked/<NAME>` file
  remains — the user must delete it manually or it will show up in future `resume` discoveries.

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

- **New-dirt cascading** — if task N fails and leaves **new** uncommitted changes (beyond the baseline), the chain stops at step 9's `comm -23` check. Pre-existing dirt (present before the run) is ignored. Surface this in the post-run summary so the user knows to clean up.
- **File both baseline-dirty and task-edited** — if the agent edits a file that was already dirty before the run, `comm -23` sees it in both baseline and current → treated as pre-existing → does NOT stop the chain. The agent's edits to that file are already staged/committed via the explicit-path commit; the residual (uncommitted portion, if any) is left for the user. There is no way to automatically separate the pre-task state from the agent's edits in a file that was dirty at start. Do not attempt to reconstruct it — leave as-is and note it in the run summary.
- **Card stuck in `progress/` or `test/`** — the autonomous run never auto-reopens a failed card. The next at-job for that card needs the user to fix and rerun manually, or move it back to `todo/` explicitly.
- **Park: base card vs. branch annotation divergence** — after park, the card in `progress/` on base is in its pre-park state (no `## ⏸ Parked` section). The full annotation lives only on `task/<NAME>` + the `.parked/` index + the TG message. When the user later merges `task/<NAME>` → base, git may flag a trivial conflict on the card file (base version lacks the annotation, branch version has it). Resolution: accept the branch version.
- **Resume concurrency guard** — if `git rev-parse --abbrev-ref HEAD` returns a `task/*` branch (not base), `/schedule-tasks resume` must STOP and report which task is in progress. Switching branches mid-session could corrupt another task's WIP.
- **Dirty base during resume** — before committing anything, the orchestrator MUST first check for active runs (`atq` + byobu window scan). If any at-job is queued OR a run appears in-flight → **STOP with an explicit error** ("auto-run appears active — wait for it to finish before resuming"). A bulk `git add -A && git commit` while a run is mid-flight would silently absorb that run's partial WIP into an unrelated commit, corrupting the task history. Only when no run is in-flight: perform the bulk commit-all-at-once and report exactly what was committed to the user. *(Intentional asymmetry: resume is a deliberate, interactive user action guarded by the active-run check, so bulk-commit is safe here. The no-bulk-stage rule governs the autonomous run only, where pre-existing uncommitted work must be preserved untouched.)*
- **`tg-notify` not configured** — park/fail/skip pings silently no-op; the run itself is unaffected — it still parks, chains, and emits `AUTO-RUN-RESULT`. The user just isn't pinged.
- **Park index orphan** — if the resumed task fails qa or review, `.parked/<NAME>` is not deleted automatically. It persists and appears in future `resume` listings. User must clean it manually: `rm $HOME/.local/state/claude-auto-runs/<PROJECT>/.parked/<NAME>`.
- **Long task overruns its slot** — slot is just `at` firing time; nothing kills the previous claude. Two windows can run in parallel. The second window will proceed despite the dirty tree but the chain dirty-check (step 9) may stop after the second card if the first run left uncommitted changes that the second run's baseline did not see. Warn the user when scheduling heavy cards close together (<60 min apart).
- **Byobu session killed** — outer script auto-creates a detached session `1`; user reattaches with `byobu attach` to see the window.
- **`cron` vs. `at`** — never use cron for one-shot; it leaves a recurring entry unless self-removed. `at` is the right primitive.
- **Permissions** — `--dangerously-skip-permissions` skips ALL approvals; only use for scheduled autonomous runs the user explicitly requested.
- **Self-chain runaway** — a chain advances on `ok`, `park`, or `skip`; the agent arms exactly one `at` job (+20 min) for the single next card, so at most one chained job is ever queued. Only new uncommitted task changes at step 9, atd inactive, or no eligible next card stops the chain.
- **Agent skipped the `at` call** — chain silently stops. Mitigated: step 9 of the prompt tells the agent to verify `at` printed a job id; the inner script emits a loud `[inner] WARN: result=ok but no at-job queued` in meta.log + the window. It does NOT auto-reschedule (no double-run risk).
- **Manual batches + self-chain coexist** — they CAN both be active, but you'll get double-booked windows. Pick one mode or the other.
- **`.chain-conditions` orphan when the chain stops abnormally** — cleanup only fires on `AUTO-RUN-NEXT: none` (clean chain end). If the chain instead stops on atd-off / no-eligible-card / new uncommitted dirt on base, the file persists. The next `/schedule-tasks` orchestrator overwrites it, so users running through the orchestrator are fine. But if the user re-arms a single card with raw `at` (skipping `/schedule-tasks`), they silently inherit stale conditions from the previous chain. Workaround: `rm $HOME/.local/state/claude-auto-runs/$(basename "$(git rev-parse --show-toplevel)")/.chain-conditions` before manual at-jobs.

## Project-agnostic guarantees

The skill is portable across repos because:

- **Scripts derive the repo from the task-file argument** — no env vars or constants to edit per repo; the scripts themselves live in the plugin cache.
- **The prompt names no project-specific agents or skills.** It tells the agent to inspect the host project's `CLAUDE.md` for subagent routing and lint/test commands; if none documented, the agent uses targeted commands for the touched files.
- **No allow/deny lists, no roadmap parsing.** Next-card selection is the related-then-lex rule in `lifecycle.md`.
- **The inner script's outcome detection** uses `AUTO-RUN-RESULT` + kanban-stage fallback — both work in any project that uses the standard `.claude/kanban/{todo,progress,test,done}/` layout.

Install this plugin and run `/schedule-tasks` from any repo — it works as-is,
provided `.claude/kanban/todo/` exists and `atd` is running.
