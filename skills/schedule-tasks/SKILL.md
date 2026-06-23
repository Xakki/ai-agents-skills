---
name: schedule-tasks
description: Schedule autonomous claude runs for kanban cards, each in its own byobu/tmux window. Triggers — RU "запланируй задачи", "запусти задачи по таймеру", "поставь в крон задачи из todo"; EN "schedule tasks", "run tasks on a timer", "auto-run kanban". Chain self-arms on ok/park/skip (+20 min); stops only on no-eligible-card or atd-off; never moves a card to done/. Escalation parks on a branch non-blocking; resume with /schedule-tasks resume.
---

## Purpose

Schedule one-shot autonomous `claude` runs for cards in `.claude/kanban/todo/`. Each job opens
a byobu window in session `1`, walks one card `todo→progress→test→ready`, then self-chains the
next card at **+20 min** on `ok`, `park`, or `skip`. Chain **STOPS** only when atd is inactive
or the backlog has no eligible card.
Final hop `ready→done` is **user-only**. Escalation parks non-blocking on a `task/*` branch;
resume via `/schedule-tasks resume`.

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
  2. implementation commit(s) (scope: `api|goclient|ext|infra|db|docs`) — code + Execution Log;
  3. `task: review <ID> (progress→test)` — git mv only, own commit;
  4. `task: ready <ID> (test→ready)` — git mv only, own commit.
  Full details → `lifecycle.md`.
- **Order** = chain picks the next card itself (related-first, then lex-oldest — see `lifecycle.md`).

Ask only for:
- **Ambiguous date/time** — "через час" / "вечером" when already past that. Skip if user gave
  `at -t YYYYMMDDhhmm`-style precision.
- **User-stated constraints** that need confirmation ("только front-* задачи", "не трогай DB",
  "после каждой задачи e2e" — confirm prefix / scope / command).

Capture any constraints verbatim — they go into `.chain-conditions` (step 3).

### 2. Verify pre-conditions

```bash
systemctl is-active atd
tmux -S /tmp/tmux-1000/default has-session -t 1   # outer script auto-creates if absent
ls .claude/kanban/todo/                            # confirm at least one card
which claude                                       # ~/.local/bin/claude expected
test -x "${CLAUDE_PLUGIN_ROOT}/scripts/run-claude-task.sh"
test -x "${CLAUDE_PLUGIN_ROOT}/scripts/run-claude-task-inner.sh"
```

> `${CLAUDE_PLUGIN_ROOT}` is inlined by Claude Code — not a real shell env var; don't `echo` it.

### 3. Conditions propagation (if user gave constraints)

Write user constraints to a single file all chain links read:

```bash
REPO="$(git rev-parse --show-toplevel)"
PROJECT_NAME="$(basename "$REPO")"
COND_FILE="$HOME/.local/state/claude-auto-runs/$PROJECT_NAME/.chain-conditions"
mkdir -p "$(dirname "$COND_FILE")"
cat > "$COND_FILE" <<'EOF'
- Не пушить и не открывать PR.
- Используй sonnet для имплементации.
EOF
```

Replace example lines with actual constraints. Skip if no constraints.
Full propagation lifecycle → `reference.md`.

### 4. Schedule first card only

> Always use `at -t CCYYMMDDhhmm` (never `at HH:MM` — midnight ambiguity; never `tomorrow` —
> drifts). Schedule **only the first card** — chain self-arms the rest.

```bash
REPO="$(git rev-parse --show-toplevel)"
TASK_DIR="$REPO/.claude/kanban/todo"
RUNNER="${CLAUDE_PLUGIN_ROOT}/scripts/run-claude-task.sh"
FIRST="$(ls "$TASK_DIR" | sort | head -1)"
echo "$RUNNER $TASK_DIR/$FIRST" | at -t 202605260330
```

### 5. Verify

```bash
atq | sort -k 4      # one job expected (chain takes over)
at -c <N> | tail -3  # confirm what will run
```

Tell user: `<time> → <first task>`; "chain arms next card automatically; cancel with `atrm <N>`".
If `.chain-conditions` was written, show its path and content.

## Self-chaining

On **ok**, **park**, or **skip**: agent calls `select-next-task.sh` to pick the next unblocked
card from `todo/` and enqueues it via `at -t +20min`. Cards that depend on a currently-parked
task are skipped automatically. Chain **STOPS** only on: atd inactive, no eligible next card,
or new uncommitted paths on base beyond the pre-run baseline. At most one chained job is ever
queued. Kill in-flight: `atq` → `atrm <N>`. Full chain mechanics → `reference.md`.

## Escalation = park & advance (non-blocking)

On a blocker, arch/logic decision, qa-fail, review-fail, or merge-conflict, the agent parks:
1. (If on base due to merge-conflict) `git switch "task/<NAME>"`.
2. Annotates the card with `## ⏸ Parked — <REASON>` (branch, problem, proposed options/default).
3. Calls `park-task.sh` — stages extra WIP (baseline-aware), commits `wip(park): <NAME> (<REASON>)`, returns to base, writes `.parked/<NAME>` index.
4. Sends **tg-notify**: task name, branch, problem summary + options, how to resume.
5. Runs the **chain step** (step 9 via `select-next-task.sh`) → next unblocked card at +20 min.
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
4. **Merge**: when the task lands in `ready/` on the branch, merge to base:
   `git switch <BASE_BRANCH>` → `git merge --no-ff --no-edit "task/<NAME>"` → `git branch -d "task/<NAME>"`.
   On merge conflict → resolve manually; do NOT auto-park from resume (interactive, user present).
5. **Cleanup**: after the merge, delete `$LOG_DIR/.parked/<NAME>`.
6. **Done**: `ready→done` is **user-only** — do not perform it autonomously.

## Cancellation

```bash
atq                                          # find job numbers
atrm <N>                                     # cancel one
atq | awk '{print $1}' | xargs -r atrm      # cancel ALL — warn user first
```

## Stop conditions (do NOT)

- DO NOT schedule without confirming date/time if ambiguous
- DO NOT queue a task not in `todo/`
- DO NOT use `cron` for one-shot — use `at`
- DO NOT push / merge / open PRs from the autonomous prompt
- DO NOT put `--debug-file` inside the repo (ENOENT risk; see `reference.md`)
- DO commit `task: start <ID> (todo→progress)` as its OWN commit — never bundle the start mv with implementation
- DO NOT instruct the prompt to move a card into `done/` — user-only step
- DO NOT start a card from `grooming/` — chain only consumes `todo/`
- DO NOT use `--no-verify`
- DO NOT use `AskUserQuestion` in the autonomous prompt — escalation parks the task instead (non-blocking)
- DO NOT make `wip(park)` commits on the base branch — park commits are only allowed on `task/*` branches
- DO NOT bulk-stage: never `git add -A`, `git add .`, `git add -u`, `git commit -a` — always stage explicit paths only
