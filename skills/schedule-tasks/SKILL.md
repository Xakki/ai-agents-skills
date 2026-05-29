---
name: schedule-tasks
description: Use when the user wants to schedule autonomous claude runs of kanban tasks at specific times — each task opens in its own byobu/tmux window. Triggers — RU "запланируй задачи", "запусти задачи по таймеру", "поставь в крон задачи из todo"; EN "schedule tasks", "run tasks on a timer", "auto-run kanban".
---

## Purpose

Schedule one-shot autonomous `claude` runs for cards in `.claude/kanban/todo/`.
Each fired job opens a new window in byobu session `1`
(`tmux -S /tmp/tmux-1000/default`) and launches
`claude --dangerously-skip-permissions` with a prompt that drives the kanban
lifecycle for one card (todo → progress → test → ready). The final hop
`ready → done` is **user-only** (kanban contract — autonomous runs don't
declare a card "done"). On a green outcome (`ok` = card landed in `ready/`)
the agent self-chains the next card at **+20 min**. On `fail` / `skip` /
empty backlog the chain **STOPS** — no further jobs queued.

This skill is **project-agnostic**: the runner scripts ship inside the plugin
(`${CLAUDE_PLUGIN_ROOT}/scripts/*.sh`) and the prompt discovers
subagents/test-commands from the host project's `CLAUDE.md`. Install this plugin
and run `/schedule-tasks` from any repo that uses the
`.claude/kanban/{todo,progress,test,ready,done}/` layout — it works as-is
(`ready/` is auto-created on first transition). The kanban board itself still
lives in the **target project** under `.claude/kanban/`; only the scripts come
from the plugin cache.

Full lifecycle + next-task selection → `lifecycle.md`.
Script internals, session-id, JSONL paths, edge cases → `reference.md`.

## Tools

| Tool                                | Purpose                                  |
|-------------------------------------|------------------------------------------|
| `at` / `atq` / `atrm` / `at -c <N>` | One-shot scheduler (preferred over cron) |
| `tmux -S /tmp/tmux-1000/default`    | Talk to the user's byobu session         |

`atd` must be active (`systemctl is-active atd`).

## Workflow

### 1. Clarify with the user — ASK ONLY when needed

Defaults (do NOT ask):
- **Branch** = current branch (typically `master`). Commit shape per card:
  **2 commits** —
  1. `task: <ID> impl` — bundles `git mv todo→progress` + all implementation
     + Execution Log updates;
  2. `task: review <ID> (progress→test→ready)` — bundles `git mv progress→test`
     + `git mv test→ready`, no content edits.

  Optional extra: `wip: pre-task auto-commit before <ID>` if the tree was
  dirty at start. The chain never moves the card to `done/` — that's the
  user's manual step from `ready/`.
- **Order** = the autonomous run picks the next card itself (related-first,
  then lexicographic — see `lifecycle.md`). Do not ask the user.

Ask **only** in these cases:
- **Date/time is ambiguous.** The user said "через час" / "вечером" / "сегодня"
  but it's already past that — confirm absolute timestamp. Skip the question if
  the user already gave `at -t YYYYMMDDhhmm`-style precision.
- **User mentioned conditions** that need clarification (e.g. "запусти только
  front-* задачи" — confirm prefix; "не трогай DB" — confirm scope; "после
  каждой задачи прогон e2e" — confirm test command).

**Capture user-provided conditions verbatim** — any constraint the user states
("do NOT push", "always run integration tests", "use sonnet for impl", "ставь
заглушку вместо реальных запросов", branch preference, anything) goes into
`conditions.txt` and propagates to every chained task. See **Conditions
propagation** below.

Post-success location is **fixed by the kanban contract** (see `lifecycle.md`):
green → `ready/` (user does `ready→done` manually later), red qa stays in
`progress/`, red review stays in `test/`. Never ask about that.

### 2. Verify pre-conditions

```bash
systemctl is-active atd                              # must be "active"
tmux -S /tmp/tmux-1000/default has-session -t 1      # outer script auto-creates if absent
ls .claude/kanban/todo/                              # confirm at least one card to start with
which claude                                         # ~/.local/bin/claude expected
test -x "${CLAUDE_PLUGIN_ROOT}/scripts/run-claude-task.sh"        # outer script present + executable
test -x "${CLAUDE_PLUGIN_ROOT}/scripts/run-claude-task-inner.sh"  # inner script present + executable
```

> `${CLAUDE_PLUGIN_ROOT}` is **substituted inline** into this skill's text by
> Claude Code — you'll see the resolved absolute plugin path, not the literal
> token. Don't `echo "$CLAUDE_PLUGIN_ROOT"` expecting a shell env var: it is
> not exported into the Bash tool's shell, only inlined into skill content.

> **No dirty-tree check here.** The autonomous run itself commits any pending
> WIP as its very first action (`wip: pre-task auto-commit before <ID>`), so
> the orchestrator does not need to commit before scheduling. See the inner
> script's step 1.

### 3. Conditions propagation (sequential chain inherits user conditions)

If the user gave constraints in step 1, write them to a single file that **all
links in the chain** read:

```bash
REPO="$(git rev-parse --show-toplevel)"
PROJECT_NAME="$(basename "$REPO")"
COND_FILE="$HOME/.local/state/claude-auto-runs/$PROJECT_NAME/.chain-conditions"
mkdir -p "$(dirname "$COND_FILE")"

# Overwrite (each /schedule-tasks invocation starts fresh). Empty content = no extra conditions.
cat > "$COND_FILE" <<'EOF'
- Не пушить и не открывать PR.
- Каждый раз прогоняй e2e только для затронутых модулей.
- Используй sonnet для имплементации, если задача не критично большая.
EOF
```

The inner script reads this file on each run and embeds it verbatim into the
autonomous prompt under "Дополнительные условия пользователя". When the chain
ends cleanly (`AUTO-RUN-NEXT: none`), the inner script deletes the file so the
next manual `/schedule-tasks` invocation isn't polluted.

If there are no conditions, skip this step — no file needed.

### 4. Schedule with `at -t CCYYMMDDhhmm`

Schedule **only the first card** — the chain self-arms the rest. Always use
**explicit absolute timestamps** (never `at HH:MM` — ambiguous around midnight;
never `tomorrow` — drifts).

```bash
TASK_DIR="$REPO/.claude/kanban/todo"
RUNNER="${CLAUDE_PLUGIN_ROOT}/scripts/run-claude-task.sh"
FIRST="$(ls "$TASK_DIR" | sort | head -1)"           # lex-oldest, same rule the chain uses

echo "$RUNNER $TASK_DIR/$FIRST" | at -t 202605260330
```

> Don't batch-schedule N cards manually — that double-books windows with the
> self-chain. Trust the chain to pull the rest.

### 5. Verify

```bash
atq | sort -k 4         # queue with timestamps (should show ONE job — the chain takes over)
at -c <N> | tail -3     # what command will run
```

Print the resulting line to the user (`time → first task`) plus a one-line
note "chain will arm the next card automatically; cancel with `atrm <N>`".
If `conditions.txt` was written, also show its content and its path.

## Self-chaining (sequential auto-pilot)

Each autonomous run does, in order:

1. **Step 1 of prompt — auto-commit any pending WIP** (leftover from previous
   chain link's usage-stats append, or any other dirty state) with message
   `wip: pre-task auto-commit before <ID>`. The chain never skip-on-dirty — it
   commits and proceeds.
2. **Steps 3–8** — walk the card through todo→progress→test→ready (per
   `lifecycle.md`). The final transition is a single commit that bundles
   both `progress→test` and `test→ready` git moves. The chain NEVER moves
   into `done/` — that's the user's call.
3. **Step 9 — chain the next card.** On a green outcome (card landed in
   `ready/`) the agent picks the next card from `.claude/kanban/todo/`
   (related-first → lex-oldest) and runs `at -t +20min` to enqueue exactly
   **one** next link. Conditions from `.chain-conditions` flow through
   automatically (the next link reads the same file). On `fail`/`skip` /
   empty backlog → no enqueue, no AUTO-RUN-NEXT.
4. **Step 10 — final marker.** Last output line: `AUTO-RUN-RESULT: <ok|fail|skip>: <ID>: <reason>`.

**Chain STOPS (by design) when any of these holds:**
- step 9 sees `fail` / `skip` outcome → no enqueue;
- `todo/` is empty / no eligible card → agent prints `AUTO-RUN-NEXT: none`, no enqueue;
- working tree dirty when step 9 evaluates → no enqueue;
- `atd` inactive → agent prints `WARN: atd inactive` + `AUTO-RUN-NEXT: none`.

A stopped chain needs **manual** re-arm (`/schedule-tasks`). The inner script
never enqueues anything — it only logs whether the agent's chain landed.

**Next-task selection rule** (in the prompt, project-agnostic): prefer a card
*related* to the one just finished (mentioned in its Acceptance Criteria,
"depends on", or shares an ID prefix); otherwise the lexicographically oldest
filename in `.claude/kanban/todo/`. No project-specific allow/deny lists.
**Cards in `grooming/` are off-limits** for the chain — they're parked because
they need clarification, not execution. Details → `lifecycle.md`.

**Kill an in-flight chain:** `atq` → `atrm <N>` for the queued +20 min job (at
most one chained link is ever queued).

## Cancellation

```bash
atq                                            # find job numbers
atrm <N>                                       # cancel one
atq | awk '{print $1}' | xargs -r atrm         # cancel ALL — warn user first
```

## Stop conditions (do NOT)

- DO NOT schedule without confirming date / branch / order with the user
- DO NOT queue a task that is not in `todo/` (the prompt will skip it, but verify first)
- DO NOT use `cron` for one-shot scheduling — use `at`
- DO NOT push / merge / open PRs from the autonomous prompt
- DO NOT put `--debug-file` inside the repo (see `reference.md` — historical ENOENT)
- DO NOT add a standalone `task: start <ID> (todo→progress)` commit — that
  `git mv` belongs inside commit 1 alongside the implementation
- DO NOT instruct the prompt to move a card into `done/` — that's user-only
  (`ready → done` is the user's manual step)
- DO NOT start a card from `grooming/` — chain only consumes `todo/`
- DO NOT use `--no-verify`

See `reference.md` for: inspecting past runs, log locations, edge cases,
script-tracking lesson, derivation variables, the autonomous prompt template.
