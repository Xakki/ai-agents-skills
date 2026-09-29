---
name: schedule-tasks
description: Schedule autonomous claude runs for Kanban cards within a user-approved, hash-verified card allowlist. A scoped run may merge after green QA/review while leaving the card in ready/; done/ remains user-only. Chain advances only inside that allowlist and never pushes or deploys.
---

## Purpose

Schedule one-shot autonomous `claude` runs for cards in `.claude/kanban/todo/`. Each job opens
a byobu window in session `1`, walks one card `todo→progress→test→ready`, then may self-chain
at **+20 min** only through the exact, previously approved scope manifest. The selected card is
the default single-card scope; every additional card requires explicit approval of its exact
basename and order. A recorded EPIC authorization may supply that list only after the caller
verifies the parent record and approved children.

Narrow scheduler exception: after green QA and independent review, an in-scope task may merge
to its recorded base while the card remains in `ready/`. This does not authorize `ready→done`,
push, or deploy. The final hop `ready→done` is always **user-only**. Escalation parks on a
`task/*` branch; resume via `/schedule-tasks resume`.

Git mechanics follow the [git-flow](../git-flow/SKILL.md) core. The autonomous
per-task branch + park-commit model and the scoped merge-at-ready exception below
are this skill's documented deltas. The manifest never authorizes bulk staging,
push, deploy, or a `done/` move.

Commit shape + lifecycle → `lifecycle.md`. Script internals, session IDs, log paths, edge
cases → `reference.md`.

## Tools

| Tool | Purpose |
|---|---|
| `at` / `atq` / `atrm` / `at -c <N>` | One-shot scheduler (preferred over cron) |
| `tmux -S /tmp/tmux-1000/default` | Talk to the user's byobu session |

`atd` must be active (`systemctl is-active atd`). Window naming format → `reference.md`.

## Workflow

### 1. Clarify with the user — ASK ONLY when needed

Defaults (do NOT ask):
- **Branch** = current branch. Commit shape per card: 4 commits (happy path) —
  1. `task: start <ID> (todo→progress)` — git mv only, own commit;
  2. implementation commit(s) (scope: `api|db|infra|docs|task`, per git-flow) — code + Execution Log;
  3. `task: review <ID> (progress→test)` — git mv only, own commit;
  4. `task: ready <ID> (test→ready)` — git mv only, own commit.
  Full details → `lifecycle.md`.
- **Scope** = exactly the initially selected card. No other `todo/` card is implicitly included.
- **Order** = exact order of the approved card list in the scope manifest.

Ask only for:
- **Ambiguous date/time** — "через час" (in an hour) / "вечером" (in the evening) when already
  past that. Skip if user gave `at -t YYYYMMDDhhmm`-style precision.
- **Scope expansion** — if more than the selected card should run, show the exact ordered
  basenames (or verify a named EPIC's recorded approved children) and obtain explicit approval
  before creating the manifest. Do not infer a batch from the backlog.
- **User-stated constraints** that need confirmation ("только front-* задачи" (only front-* tasks),
  "не трогай DB" (don't touch DB), "после каждой задачи e2e" (e2e after each task) — confirm prefix / scope / command).

Capture exact authorized card basenames in the scope manifest. Free-form `.chain-conditions`
are a separate mechanism and are not injected into the current runner prompt; do not rely on
them to enforce task scope or operational constraints. If a required constraint cannot be
enforced or safely followed, do not schedule the run.

### 2. Verify pre-conditions

```bash
systemctl is-active atd
tmux -S /tmp/tmux-1000/default has-session -t 1   # outer script auto-creates if absent
ls .claude/kanban/todo/                            # confirm at least one card
which claude                                       # ~/.local/bin/claude expected
test -x "${CLAUDE_PLUGIN_ROOT}/scripts/run-claude-task.sh"
test -x "${CLAUDE_PLUGIN_ROOT}/scripts/run-claude-task-inner.sh"
test -x "${CLAUDE_PLUGIN_ROOT}/scripts/create-task-scope.sh"
test -x "${CLAUDE_PLUGIN_ROOT}/scripts/chain-next-task.sh"
```

> `${CLAUDE_PLUGIN_ROOT}` is inlined by Claude Code — not a real shell env var; don't `echo` it.

### 3. Scope authorization

Before calling the helper, obtain explicit user approval for the exact ordered card basenames.
The helper records the canonical repository, current base branch, approval source, fixed allowed
effects, and card allowlist in a SHA-256-named manifest under the per-project run-state directory.
The one-card default requires approval for that selected card; extending the chain requires
additional exact cards or a verified recorded EPIC authorization.

```bash
REPO="$(git rev-parse --show-toplevel)"
PROJECT_NAME="$(basename "$REPO")"
TASK_DIR="$REPO/.claude/kanban/todo"
FIRST="$(ls "$TASK_DIR" | sort | head -1)"
SCOPE_OUTPUT="$("${CLAUDE_PLUGIN_ROOT}/scripts/create-task-scope.sh" --repo "$REPO" --approved --approval-source explicit-user --card "$TASK_DIR/$FIRST")"
SCOPE_ID="${SCOPE_OUTPUT#scope-id=}"
```

Repeat `--card "$TASK_DIR/<approved-basename>.md"` only for each additional card the user
approved, in the desired order. Do not use a wildcard or include all of `todo/`.

### 4. Schedule the first in-scope card

> Always use `at -t CCYYMMDDhhmm` (never `at HH:MM` — midnight ambiguity; never `tomorrow` —
> drifts). Schedule only the first card from the approved manifest. Every chained job reuses
> the same scope ID.

```bash
RUNNER="${CLAUDE_PLUGIN_ROOT}/scripts/run-claude-task.sh"
source "${CLAUDE_PLUGIN_ROOT}/scripts/task-scope.sh"
AT_COMMAND="exec $(task_scope_shell_quote "$RUNNER") $(task_scope_shell_quote "$TASK_DIR/$FIRST") $(task_scope_shell_quote "$SCOPE_ID")"
printf '%s\n' "$AT_COMMAND" | at -t 202605260330
```

### 5. Verify

```bash
atq | sort -k 4      # one initial job expected
at -c <N>            # verify task path and scope ID in the queued command
```

Tell user: `<time> → <first task>`; show the scope ID and exact authorized card list; explain
that the chain stops when that list is exhausted. Cancel with `atrm <N>`.

## Self-chaining

On **ok**, **park**, or **skip**, the prompt calls `chain-next-task.sh` once. The helper validates
the same scope ID, checks the baseline, asks `select-next-task.sh` for the next unblocked card in
the manifest's exact order, and queues one `at -t +20min` job with that scope ID. It never falls
back to another `todo/` card. The chain stops on: atd inactive, exhausted scope, no eligible
in-scope card, invalid/tampered scope, changed base branch, or new uncommitted paths beyond the
pre-run baseline. The manifest is retained as an audit record. Kill an in-flight queued job:
`atq` → `atrm <N>`. Full chain mechanics → `reference.md`.

## Escalation = park & advance (non-blocking)

On a blocker, arch/logic decision, qa-fail, review-fail, or merge-conflict, the agent parks:
1. (If on base due to merge-conflict) `git switch "task/<NAME>"`.
2. Annotates the card with `## ⏸ Parked — <REASON>` (branch, problem, proposed options/default).
3. Calls `park-task.sh` — stages extra WIP (baseline-aware), commits `wip(park): <NAME> (<REASON>)`, returns to base, writes `.parked/<NAME>` index.
4. Sends **tg-notify**: task name, branch, problem summary + options, how to resume.
5. Runs the **chain step** (step 9 via `chain-next-task.sh`) → next unblocked in-scope card at +20 min.
6. Exits with `AUTO-RUN-RESULT: park: <NAME>: parked (<REASON>)`.

`AskUserQuestion` is **never** used in the autonomous flow. Full detail → `reference.md`.

## Resume a parked task

Run `/schedule-tasks resume [<NAME>]` in the main thread (interactive, not scheduled):

1. **Discover**: read `$HOME/.local/state/claude-auto-runs/<PROJECT>/.parked/`. If `<NAME>` given
   → use it; if exactly one parked task → use it; else list them and ask the user which.
2. **Concurrency guard**: inspect `CUR=$(git rev-parse --abbrev-ref HEAD)`.
   - If `CUR == "task/<NAME>"` → already on the right branch; skip straight to step 3 (no switch needed).
   - If `CUR` is a **different** `task/*` branch → **STOP**; report which task/branch is active; do not switch.
   - If `CUR` == base:
     - Check for active runs first: `atq` (any at-jobs queued?) and inspect byobu windows for an active auto-run. If a run appears in-flight → **STOP with an explicit error** ("auto-run appears active — wait for it to finish before resuming"). Do NOT commit.
     - Only when no run is in-flight: if the tree is dirty → commit everything at once:
       `git add -A && git commit -m "chore: wip on <base> before resume <NAME>"` and **report** to
       the user exactly what was committed. *(Bulk-commit is safe here: resume is a user-initiated
       action guarded by the active-run check. The no-bulk-stage rule applies to the autonomous run
       only.)*
     - Then `git switch task/<NAME>`.
3. **Resume work**: read the card's `## ⏸ Parked` section, apply the user's answer, continue
   implementation, run qa-check, then `progress→test→ready` on the branch.
4. **Merge**: after QA/review pass, when the task lands in `ready/` on the branch, merge to base:
   `git switch <BASE_BRANCH>` → `git merge --squash "task/<NAME>"` → `git commit -m "task: <NAME> merged (ready)"` (one squash commit) → `git branch -m "task/<NAME>" "done/<NAME>"` (archive, do not delete). The card remains in `ready/`.
   On merge conflict → resolve manually; do NOT auto-park from resume (interactive, user present).
5. **Cleanup**: after the merge, delete `$LOG_DIR/.parked/<NAME>`.
6. **Done**: `ready→done` is **user-only** — do not perform it in the scheduled prompt or resume flow.

## Cancellation

```bash
atq                                          # find job numbers
atrm <N>                                     # cancel one
atq | awk '{print $1}' | xargs -r atrm      # cancel ALL — warn user first
```

## Stop conditions (do NOT)

- DO NOT schedule without confirming date/time if ambiguous
- DO NOT queue a task not in `todo/` or outside the hash-verified scope manifest
- DO NOT use `cron` for one-shot — use `at`
- DO NOT push, deploy, or open PRs from the autonomous prompt
- In the scheduled prompt, DO NOT merge without a valid scope manifest and green QA + independent review; merge is allowed only in step 8 and the card stays in `ready/`. Interactive resume uses its own reviewed merge step.
- DO NOT extend the manifest or advance to an unlisted task
- DO NOT put `--debug-file` inside the repo (ENOENT risk; see `reference.md`)
- DO commit `task: start <ID> (todo→progress)` as its OWN commit — never bundle the start mv with implementation
- DO NOT instruct the prompt to move a card into `done/` — user-only step
- DO NOT start a card from `grooming/` — chain only consumes `todo/`
- DO NOT use `--no-verify`
- DO NOT use `AskUserQuestion` in the autonomous prompt — escalation parks the task instead (non-blocking)
- DO NOT make `wip(park)` commits on the base branch — park commits are only allowed on `task/*` branches
- DO NOT bulk-stage: never `git add -A`, `git add .`, `git add -u`, `git commit -a` — always stage explicit paths only
