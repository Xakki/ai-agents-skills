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

| Script                         | Role |
|--------------------------------|------|
| `run-claude-task.sh`           | Outer: validates the exact task and scope ID before opening a tmux window in byobu session `1`; restarts a detached session if needed and passes the scope ID to the inner script. Invoked by `at`. |
| `run-claude-task-inner.sh`     | Inner: validates the scope again, takes a per-scope lock, captures baseline dirty-set, builds the scoped prompt, runs `claude --dangerously-skip-permissions`, derives outcome, logs usage stats, and verifies/cancels the queued continuation. Releases the lock before waiting for the user to close the window. |
| `park-task.sh`                 | Deterministic park: ensure on `task/<NAME>` branch, stage extra paths (baseline-aware, no bulk-stage), commit `wip(park): <NAME> (<REASON>)`, switch back to base, write `.parked/<NAME>` index. Args: `<TASK_FILE> <BASE_BRANCH> <BASELINE_FILE> <SESSION_ID> <LOG_DIR> <REASON>`. REASON ∈ qa-fail\|review-fail\|blocker\|question\|merge-conflict. |
| `create-task-scope.sh`         | Creates a read-only, SHA-256-named manifest after caller-obtained approval. Args: `--repo DIR --approved --approval-source SOURCE --card TODO_CARD.md [--card TODO_CARD.md ...]`; prints `scope-id=<digest>`. |
| `task-scope.sh`                | Shared manifest, repository, branch, digest, and card-path validation sourced by the other scripts. |
| `select-next-task.sh`          | Selects the next unblocked card only from the exact scope list, preserving list order. Prints basename or `none`. Args: `<REPO> <PARKED_DIR> <JUST_FINISHED_NAME> <SCOPE_ID>`. |
| `chain-next-task.sh`           | Checks baseline and atd, calls the scope-limited selector, and queues exactly one next card with the same scope ID. |
| `view-task-history.sh`         | Pretty-print any past run by session-id, task-name, or `--list`. |
| `summarize-task-usage.sh`      | Aggregate per-model token usage + approximate cost from the session JSONL; appends an "Auto-run usage" block to the task file. Called once at end of the inner run. |

**Scripts live in the immutable plugin cache** (`${CLAUDE_PLUGIN_ROOT}/scripts/`)
— they are not copied into, or tracked by, the target repo. Historical lesson
that shaped the design: an earlier autonomous prompt did `git stash -u` and
*vanished* in-repo untracked scripts mid-run. The current prompt forbids
`git stash` and any bulk-staging; with scripts out of the repo entirely
the failure mode is gone.

## Derived variables (in every script)

`SCRIPT_DIR` (own location) locates sibling scripts in the plugin cache. The
target repo is resolved with `git -C <task-file-directory> rev-parse
--show-toplevel`; the task path is canonicalized with `realpath`. This supports
both `.claude/kanban` and a `.claude` alias to `.agents/kanban`.

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # plugin cache scripts/
TASK_FILE="$(realpath -e -- "$1")"                         # canonical card path
SCOPE_ID="$2"                                                # SHA-256 manifest id
PROJECT_DIR="$(git -C "$(dirname "$TASK_FILE")" rev-parse --show-toplevel)"
PROJECT_NAME="$(basename "$PROJECT_DIR")"                     # e.g. myproject
CLAUDE_PROJECT_PATH="$(printf '%s' "$PROJECT_DIR" | tr '/' '-')"
                                                             # e.g. -home-user-myproject
```

`CLAUDE_PROJECT_PATH` is Claude Code's on-disk encoding of an absolute project
path under `~/.claude/projects/` (every `/` → `-`). Used to find the per-run
session JSONL.

Use the same derivation in ad-hoc shell snippets for this skill — the
SKILL.md examples assume `REPO=$(git rev-parse --show-toplevel)`.

## Approved scope manifest

`create-task-scope.sh` writes one manifest per scheduled chain under
`$LOG_DIR/scopes/<SHA-256>.manifest`. It records format version, canonical repo
path, current base branch, approval source/time, fixed permissions/forbidden
actions, and exact ordered card basenames. The manifest is made read-only; the
digest is rechecked on every job. The runner also requires the same repo and base
branch and rejects cards outside the manifest before opening tmux/Claude.
The creator and loader reject symlinked run-state, project, and `scopes/`
directories and verify that their canonical paths remain under the expected
`$HOME/.local/state/claude-auto-runs/<project>/` location.

Create the manifest only after explicit approval of the exact card list:

```bash
SCOPE_OUTPUT="$("${CLAUDE_PLUGIN_ROOT}/scripts/create-task-scope.sh" \
  --repo "$REPO" --approved --approval-source explicit-user \
  --card "$REPO/.claude/kanban/todo/<FIRST>.md" \
  --card "$REPO/.claude/kanban/todo/<SECOND>.md")"
SCOPE_ID="${SCOPE_OUTPUT#scope-id=}"
```

`--approved` is a caller attestation, not an interactive approval mechanism.
For `recorded-epic:<ID>`, the caller must verify the named EPIC's recorded
authorization and exact approved children before creating the manifest. Never
use wildcards or infer scope from the full backlog. A one-card scope is the
default; each additional card requires explicit approval.

The manifest permits execute, QA, review, merge-at-ready, and chaining only
within its exact list. It never permits a `done/` move, push, or deploy. Missing,
malformed, modified, wrong-repo, wrong-base, or out-of-scope requests fail closed.
The inner runner rejects a symlink at the per-scope lock path, opens the file
append-only, and checks its canonical path and device/inode against the open fd
before `flock`; this avoids truncating a redirected target. The lock serializes
duplicate jobs in that scope. It releases the lock after task/queue verification, before
waiting for the user to close the window. Completed manifests are retained as audit
records.

## Session id, JSONL, debug log

The inner script generates a UUID `SESSION_ID` and passes it to claude as
`--session-id`. Two outputs result:

- `$LOG_DIR/<TS>_<task>.meta.log` — start/end markers, session id, resume hint, usage summary
- `$LOG_DIR/<TS>_<task>.debug.log` — claude's `--debug-file` output
- `~/.claude/projects/$CLAUDE_PROJECT_PATH/<SESSION_ID>.jsonl` — every prompt, tool call, and tool result (Claude Code writes this regardless)
- `$LOG_DIR/.baseline-dirty-<TS>` — `git status --porcelain` snapshot taken **before** claude runs. Read by (a) the chain helper via `comm -23` to detect only new uncommitted task changes, and (b) the end-of-run auto-commit block to identify new kanban `.md` paths to stage. Deleted after outcome/queue verification and before the interactive window wait. If the file is missing at chain step time, the chain stops safely.

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
   `todo/` so the selector won't re-pick it), then creates `task/<NAME>`. All impl,
   QA, and review commits land on the branch. The exact approved scope manifest
   permits merge-at-ready after green QA and independent review, leaving the
   card ready under that grant alone. An independent valid `done` grant may
   finalize the card and commit its exact update; push/deploy also require their
   own action-specific grants. Verify an authorized squash merge and its base
   commit/card locations before archiving as `done/<NAME>`. If merge is ungranted
   or blocked, retain the task branch and its ready/done card, preserve unrelated
   dirt, and safely return to base before chaining; report the canonical base as
   unmerged. Stop before chaining if a safe return is impossible. On failure,
   `park-task.sh` commits WIP on the branch and returns to base; the branch stays
   unmerged.
3. **Chain step (step 9, on ok/park/skip).** The prompt calls
   `chain-next-task.sh` once. The helper verifies the baseline, asks
   `select-next-task.sh` for the next unblocked card in the approved manifest,
   and queues exactly one `at -t +20min` job carrying the same scope ID. It never
   falls back to the general TODO backlog.
4. **Final marker (last step of the prompt)** is non-negotiable:
   `AUTO-RUN-RESULT: <ok|park|skip>: <ID>: <reason>` (no markdown / quotes / trailing text).
   Emitted *after* the chain step.
5. **The inner script verifies the helper-owned enqueue.** It only:
   - parses `AUTO-RUN-RESULT` from the JSONL; missing or malformed markers become `unknown`, cancel the scoped continuation, and stop the chain (there is no Kanban-stage fallback);
   - looks for an `AUTO-RUN-NEXT: <basename>.md|none` marker in the JSONL and compares a complete `at -c` command line with the exact shell-quoted runner, TODO-card path, and scope ID; substring matches are not accepted;
   - cancels only exact task command lines; scope-wide cleanup checks complete commands for cards in the validated manifest, and refuses broad cancellation when the manifest is invalid;
   - emits loud `[inner] WARN:` / `[inner] ERROR:` lines in `meta.log` and the window when a declared continuation has no matching queued job. It does NOT auto-reschedule (avoids double-runs).
6. **+20 min gap.** The next job is queued only after the current task/QA/review/merge-or-park flow is finished. The inner script verifies the queued command, then releases the per-scope lock before its interactive `read`; leaving the previous window open therefore does not block the next run.

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
5. Run **chain step 9** (`chain-next-task.sh` picks the next unblocked in-scope card at +20 min).
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

## Legacy `.chain-conditions` (not enforced)

The free-form `$LOG_DIR/.chain-conditions` mechanism is not written by the
current workflow and is not read or injected by `run-claude-task-inner.sh`.
Do not rely on it for scope or operational constraints. The scope manifest
enforces only its documented fixed permissions and exact card allowlist. If a
required non-scope condition cannot be supplied to and safely followed by the
scheduled prompt, do not schedule the run.

## Edge cases / risks

- **New-dirt cascading** — if task N fails and leaves **new** uncommitted changes (beyond the baseline), the chain stops at step 9's `comm -23` check. Pre-existing dirt (present before the run) is ignored. Surface this in the post-run summary so the user knows to clean up.
- **File both baseline-dirty and task-edited** — if the agent edits a file that was already dirty before the run, `comm -23` sees it in both baseline and current → treated as pre-existing → does NOT stop the chain. The agent's edits to that file are already staged/committed via the explicit-path commit; the residual (uncommitted portion, if any) is left for the user. There is no way to automatically separate the pre-task state from the agent's edits in a file that was dirty at start. Do not attempt to reconstruct it — leave as-is and note it in the run summary.
- **Card stuck in `progress/` or `test/`** — the autonomous run never auto-reopens a failed card. The next at-job for that card needs the user to fix and rerun manually, or move it back to `todo/` explicitly.
- **Park: base card vs. branch annotation divergence** — after park, the card in `progress/` on base is in its pre-park state (no `## ⏸ Parked` section). The full annotation lives only on `task/<NAME>` + the `.parked/` index + the TG message. When the user later merges `task/<NAME>` → base, git may flag a trivial conflict on the card file (base version lacks the annotation, branch version has it). Resolution: accept the branch version.
- **Resume concurrency guard** — if `git rev-parse --abbrev-ref HEAD` returns a `task/*` branch (not base), `/schedule-tasks resume` must STOP and report which task is in progress. Switching branches mid-session could corrupt another task's WIP.
- **Dirty base during resume** — before committing anything, the orchestrator MUST first check for active runs (`atq` + byobu window scan). If any at-job is queued OR a run appears in-flight → **STOP with an explicit error** ("auto-run appears active — wait for it to finish before resuming"). A bulk `git add -A && git commit` while a run is mid-flight would silently absorb that run's partial WIP into an unrelated commit, corrupting the task history. Only when no run is in-flight: perform the bulk commit-all-at-once and report exactly what was committed to the user. *(Intentional asymmetry: resume is a deliberate, interactive user action guarded by the active-run check, so bulk-commit is safe here. The no-bulk-stage rule governs the autonomous run only, where pre-existing uncommitted work must be preserved untouched.)*
- **`tg-notify` not configured** — park/fail/skip pings silently no-op; the run itself is unaffected — it still parks, chains, and emits `AUTO-RUN-RESULT`. The user just isn't pinged.
- **Park index orphan** — if the resumed task fails qa or review, `.parked/<NAME>` is not deleted automatically. It persists and appears in future `resume` listings. User must clean it manually: `rm $HOME/.local/state/claude-auto-runs/<PROJECT>/.parked/<NAME>`.
- **Different scopes can overlap** — the lock prevents concurrent duplicate runs for one scope ID, not independent approved scopes or manually scheduled jobs. Avoid arming overlapping chains in the same repository; separate windows could contend for the same branch/worktree. The next job in one chain is scheduled only after its current task finishes.
- **Byobu session killed** — outer script auto-creates a detached session `1`; user reattaches with `byobu attach` to see the window.
- **`cron` vs. `at`** — never use cron for one-shot; it leaves a recurring entry unless self-removed. `at` is the right primitive.
- **Permissions** — `--dangerously-skip-permissions` skips ALL approvals; only use for scheduled autonomous runs the user explicitly requested.
- **Self-chain runaway** — a chain advances on `ok`, `park`, or `skip`, but only within the finite approved manifest. One next job is queued at a time. New uncommitted task paths, inactive atd, exhausted/blocked scope, invalid manifest, or a changed base branch stop the chain.
- **Agent skipped the `at` call** — chain silently stops. Mitigated: step 9 of the prompt tells the agent to verify `at` printed a job id; the inner script emits a loud `[inner] WARN: result=ok but no at-job queued` in meta.log + the window. It does NOT auto-reschedule (no double-run risk).
- **Manual batches + self-chain coexist** — they can both be active. The per-scope lock does not coordinate unrelated manual jobs or a different scope ID. Avoid overlapping work in the same repository.

## Project-agnostic guarantees

The skill is portable across repos because:

- **Scripts derive the repo from the task-file argument** — no env vars or constants to edit per repo; the scripts themselves live in the plugin cache.
- **The prompt names no project-specific agents or skills.** It tells the agent to inspect the host project's `CLAUDE.md` for subagent routing and lint/test commands; if none documented, the agent uses targeted commands for the touched files.
- **The manifest is the explicit allowlist.** Selection preserves its recorded order and never adds cards from the general backlog or parses a roadmap.
- **The inner script's outcome detection** uses `AUTO-RUN-RESULT` only; missing/garbled markers stop the chain. There is no Kanban-stage fallback.

Install this plugin and run `/schedule-tasks` from any repo — it works as-is,
provided `.claude/kanban/todo/` exists and `atd` is running.
