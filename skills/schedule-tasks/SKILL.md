---
name: schedule-tasks
description: Schedule autonomous claude runs for kanban cards, each in its own byobu/tmux window. Triggers — RU "запланируй задачи", "запусти задачи по таймеру", "поставь в крон задачи из todo"; EN "schedule tasks", "run tasks on a timer", "auto-run kanban". Chain self-arms on success (+20 min); stops on fail/skip; never moves a card to done/.
---

## Purpose

Schedule one-shot autonomous `claude` runs for cards in `.claude/kanban/todo/`. Each job opens
a byobu window in session `1`, walks one card `todo→progress→test→ready`, then on a green
outcome self-chains the next card at **+20 min**. Chain **STOPS** on `fail`/`skip`/empty
backlog. Final hop `ready→done` is **user-only**.

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

On `ok` (card landed in `ready/`): agent picks the next card from `todo/` (related-first →
lex-oldest) and enqueues it via `at -t +20min`. On `fail`/`skip`/empty backlog/dirty tree:
chain **STOPS** — manual re-arm needed (`/schedule-tasks`). At most one chained job is ever
queued. Kill in-flight: `atq` → `atrm <N>`. Full chain mechanics → `reference.md`.

## Escalation & Telegram notifications

The run pings **tg-notify** (main thread only — subagents never notify) in exactly three cases:
escalation (blocker / arch-changing decision), terminal `fail`, terminal `skip` (dirty tree).
No ping on `ok`. Soft dependency on `TELEGRAM_BOT_TOKEN`/`TELEGRAM_CHAT_ID`. While blocked on
an escalation question the chain's next `at` is NOT armed. Full detail → `reference.md`.

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
