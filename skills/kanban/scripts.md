# kanban — scripts reference

Full CLI for the script-driven ID/automation layer. Read this when you need a
flag, the lock-file format, or a worked example beyond the [SKILL.md](SKILL.md)
happy path. All scripts live in `skills/kanban/scripts/`, invoked as:

```bash
ROOT="${AI_AGENTS_SKILLS_ROOT:-${CLAUDE_PLUGIN_ROOT:-${PLUGIN_ROOT:-${CURSOR_PLUGIN_ROOT:-}}}}"
"$ROOT"/skills/kanban/scripts/<name> [--repo <path>] ...
```

The portable root chain prefers Hermes' `AI_AGENTS_SKILLS_ROOT`, then the
Claude/Codex/Cursor runtime-specific plugin roots. Usage synopses below omit
the `"$S"/` prefix (`S="$ROOT/skills/kanban/scripts"`, see [SKILL.md](SKILL.md))
for brevity — prepend it when invoking. `--repo <path>` is optional
on every script; default is the
git toplevel of the CWD. Every script prints its result value on **stdout**
and human-readable notices on **stderr** — safe to capture stdout into a
variable.

**Manual fallback.** These scripts are the default path, not a hard
requirement — if a script is unavailable, allocate the ID by hand against
`.claude/kanban.lock` (format below), write the card from
[task-template.md](task-template.md), and move it with
[git-move](../git-move/SKILL.md) directly.

## `.claude/kanban.lock`

Counter file, one per repo, **committed to git**:

```
# kanban ID counters — managed by kanban-id.sh. Commit this file.
prefix=AVF
AVF=42
PERF=7
```

- `prefix=` — the project's default prefix (used when a script isn't given
  `--prefix`/`PREFIX` explicitly).
- Every other `KEY=value` line is the last-used number for that prefix
  (multi-prefix repos are supported — e.g. a `PERF` task living alongside the
  default `AVF` cards).
- **Allocation is `flock`-guarded.** The actual OS lock is a stable companion
  file, `.claude/kanban.lock.flock` — NOT `kanban.lock` itself, which is
  replaced via `mktemp`+`mv` on every write and would make a direct `flock`
  on it a TOCTOU (a waiter that opened the pre-rename inode is silently
  disconnected from whoever opens the new one). The `.flock` file (and, on
  systems without `flock`, a `.lockdir` mkdir-spinlock fallback) is a pure
  lock marker — don't commit it, it carries no data of its own.
- **Reconcile-on-allocate.** Every `next`/`epic`/`sub` call scans the actual
  cards on the board (all stage dirs) for the highest existing number under
  that prefix and computes `next = max(counter_in_lock, max_number_on_board) +
  1`, then writes the result back. This means a stale lock file (e.g. after a
  merge that brought in cards allocated on another branch) can never hand out
  a duplicate ID — the board is the source of truth, the lock file is a fast
  cache.

## Prefix reservation

A script resolves which prefix to use for an allocation in this order:

1. An explicit `PREFIX`/`--prefix` argument, if the caller passed one — used
   for that call. If `.claude/kanban.lock` has **no `prefix=` line yet**,
   this explicit choice IS the first-use confirmation, so it's persisted as
   the project default too (with the same stderr notice as every other
   persist path below). It never *overrides* an already-recorded different
   default, though — pass it every time if that's what you want for one call.
2. `prefix=` already in `.claude/kanban.lock` — nothing to resolve, no
   confirmation needed, read-only.
3. **Otherwise, confirmation is required — nothing is ever auto-picked.**
   The board's dominant existing prefix (scan all cards, count per prefix,
   most-frequent wins, ties broken by the highest existing card number) or,
   on a genuinely empty board, a dir-basename-derived candidate
   (`avito-fix` → `AVF`, `sa-fix` → `SAF`) is only ever a *suggestion*:
   - **`KANBAN_ASSUME_YES=1`** accepts that suggestion non-interactively and
     persists it — for autonomous/scheduled runs that must not block.
   - **An interactive terminal** (stdin AND stderr both TTYs) is prompted
     once: `Use '<candidate>' as this project's default prefix? [Y/n/<other>]`.
     Enter/`y` accepts the suggestion, `n` aborts (exit 2, nothing
     persisted), anything else is taken as a literal prefix to use instead
     (validated, then persisted).
   - **Otherwise (the default — agents, CI, scheduled runs):** prints the
     candidate list (board prefixes with counts, most frequent first, plus
     the dir-derived fallback) and exactly how to confirm, to stderr, then
     **exits 2 — no file is touched, `kanban.lock` is not even created.**
     Confirm with `kanban-id.sh set-prefix <PREFIX>` (below) or pass
     `--prefix <PREFIX>` explicitly to the mutating call (step 1).

Every path that persists a prefix — `set-prefix`, an explicit `--prefix` on
first use, a confirmed prompt answer, or `KANBAN_ASSUME_YES=1` — funnels
through one code path that ALWAYS prints a one-line stderr notice naming the
prefix and where it was written; there is no silent persistence anywhere.

To keep two repos on the same host from picking the same prefix, persisting
also writes a row to a personal, **non-git** registry:

```
${KANBAN_PREFIX_REGISTRY:-~/.config/kanban/prefixes.tsv}
```

Format: `<PREFIX>\t<repo path>`, one row per reserved prefix. It is a
**convenience, not an authority**: persisting a prefix already registered to
a different repo path prints a stderr warning and proceeds anyway (your
confirmed choice — or an existing board's own cards — always wins); a
missing/unwritable registry is a soft warning too, never a hard failure.
Every script still works with only `.claude/kanban.lock` present.

## `kanban-id.sh` — allocate / inspect IDs

```bash
kanban-id.sh next [PREFIX]         # allocate + consume the next plain ID: PREFIX-NUM
kanban-id.sh epic [PREFIX]         # allocate + consume the next epic ID: EPIC-NUM (PREFIX ignored)
kanban-id.sh sub <EPIC-ID>         # next subtask number under EPIC-ID: EPIC-ID-NN (2-digit)
kanban-id.sh peek [PREFIX]         # print the last-used number — NO allocation, no lock write
kanban-id.sh prefix                # print the default prefix — confirmation required on first use
kanban-id.sh set-prefix <PREFIX>   # confirm+persist the project's default prefix
```

- `PREFIX` defaults to the project's default prefix (`.claude/kanban.lock`
  `prefix=` line) when omitted — see [Prefix reservation](#prefix-reservation)
  for what happens when there isn't one yet.
- `next` allocates from the requested/default regular task prefix. `epic`
  allocates from the reserved `EPIC` prefix (its optional historical `PREFIX`
  argument is accepted but ignored), independently of the default task prefix;
  both consume their respective counters and reconcile against the board.
- `sub <EPIC-ID>` looks at existing `<EPIC-ID>-NN-*.md` cards across all stage
  dirs plus the lock file, returns the next unused `NN`, zero-padded to 2
  digits. Does not require `<EPIC-ID>` itself to exist yet as a card.
- `peek` is read-only — use it to preview without consuming a number. When
  `PREFIX` is omitted and no `prefix=` is recorded yet, it still answers from
  the board's dominant existing prefix (see step 3 of
  [Prefix reservation](#prefix-reservation)) without writing
  `.claude/kanban.lock` or the registry — unaffected by the confirm-required
  contract, since it never persists anything.
- `prefix` with no default recorded yet is where the confirm-required
  contract lives — see [Prefix reservation](#prefix-reservation). Exits 2
  (candidate list on stderr) unless `KANBAN_ASSUME_YES=1` is set or it's
  running in an interactive terminal.
- `set-prefix <PREFIX>` is the **explicit confirmation step**: validates the
  shape (letters/digits, starting with a letter), writes `prefix=<PREFIX>` to
  the lock file, appends the registry row if free (warns, still proceeds, if
  another repo already holds it), and prints the same one-line stderr notice
  every persist path prints. Use this after asking the user which prefix to
  confirm on a project's first kanban use.

## `kanban-new.sh` — allocate + render + stage a card

```bash
kanban-new.sh --title "…" [--stage todo|grooming] [--prefix P] \
              [--epic | --sub <EPIC-ID>] [--crit Blocking|High|Medium|Minor] \
              [--tag tech-debt|feature|bug-fix]...
```

- `--title` required; everything else optional.
- `--stage` default `todo`; use `grooming` when scope isn't settled yet.
- `--epic` — allocate from the reserved `EPIC` namespace, filename
  `EPIC-<NUM>-<slug>.md`. Its `--prefix` never changes the epic ID, but on a
  board without `prefix=` it persists that ordinary-task default for later
  plain cards.
- `--sub <EPIC-ID>` — allocate via `kanban-id.sh sub <EPIC-ID>`, filename
  `<EPIC-ID>-<NN>-<slug>.md`. Mutually exclusive with `--epic`.
- Neither `--epic` nor `--sub` → plain task, `kanban-id.sh next`, filename
  `<PREFIX>-<NUM>-<slug>.md`.
- `--crit` / `--tag` prefill the matching [task-template.md](task-template.md)
  fields; omitted ones are left as the template placeholder for manual fill-in.
- Renders [task-template.md](task-template.md), writes it into the stage dir,
  `git add`s the new file (staging only — **never commits**), prints the
  card's path on stdout.

## `kanban-move.sh` — validated stage transition

```bash
kanban-move.sh <ID|path> <stage> [--force] [--approved]
```

- First arg accepts either a bare ID (`AVF-43`) — resolved by scanning stage
  dirs for a matching filename — or a full/relative path.
- `<stage>` is one of `grooming|todo|progress|test|ready|done`.
- Validates the transition before moving anything:
  - `→ done` requires `--approved`; it mechanically asserts that the caller has
    either current final user approval or recorded EPIC-scoped upfront autonomous
    authorization as defined in `SKILL.md`. Without it, exits with an error and
    no file move. The script cannot validate the authorization record itself.
  - A subtask (`<EPIC-ID>-NN-*`) cannot reach `done/` before its epic
    (`<EPIC-ID>-*`) is already in `done/`.
  - Leaving `grooming/` is blocked while the card still has a
    `**Open questions:**` section — resolve into `**Decisions:**` first (see
    `SKILL.md` grooming protocol).
  - `--force` bypasses all of the above validations for a deliberate manual
    override — use sparingly, prints a stderr warning when used.
- On success, moves the card via [git-move](../git-move/SKILL.md) (stages the
  rename, does **not** commit) and prints the suggested commit subject on
  stdout: `task: <verb> <ID> (<from>→<to>)`, where `<verb>` is
  `groom|start|review|ready|done` for the matching edge (or `move` for a
  `--force`-only/backward transition). Commit it yourself:
  ```bash
  git commit -m "$(kanban-move.sh AVF-43 progress)"
  ```

## `kanban-status.sh` — board overview

```bash
kanban-status.sh [--stage todo|grooming|progress|test|ready|done] [--epic <EPIC-ID>]
```

- No flags → counts per stage + the card list per stage; subtasks are printed
  grouped under their epic wherever the epic and subtask share a stage.
- `--stage <s>` narrows the listing to one stage.
- `--epic <EPIC-ID>` narrows to one epic and its subtasks across all stages,
  with each subtask's current stage shown inline.

## `kanban-lint.sh` — card validation

```bash
kanban-lint.sh [<ID|path>…]
```

- No args → lints every **active** card on the board; `done/` cards are
  archived and excluded. Args restrict to specific cards/IDs, but an explicit
  or implicit `done/` reference remains excluded; an implicit ID/basename
  prefers an active match when both active and archived cards match.
- Checks:
  - filename/ID shape (`<PREFIX>-<NUM>[-<NN>]-<slug>.md`, prefix matches the
    project's reserved prefix or an existing multi-prefix entry in the lock
    file);
  - required [task-template.md](task-template.md) sections present
    (`**Criticality:**`, `**TAGS:**`, `**Description:**`, `**Problem:**`,
    `**Impact:**`, `**Recommendation:**`, `**Acceptance Criteria:**`);
  - a stray `**Open questions:**` section on a card **outside** `grooming/`
    (should have been resolved into `**Decisions:**` before leaving grooming);
  - duplicate IDs across stage dirs (same `<PREFIX>-<NUM>` on two different
    card files);
  - counter drift — a card number on the board higher than
    `.claude/kanban.lock`'s recorded counter for that prefix (a lock file that
    fell behind; not fatal, `kanban-id.sh` self-heals on next allocation, but
    worth flagging before it masks a real problem).
- Prints one line per finding to stdout; clean board prints nothing.

## Exit codes (all five scripts)

| Code | Meaning |
|---|---|
| `0` | success (or, for `kanban-lint.sh`, no findings) |
| `1` | usage error — bad/missing flags or args |
| `2` | validation/not-found error — unknown ID, illegal transition, missing card, or (`kanban-lint.sh`) findings present |
| `3` | lock contention — `flock` on `.claude/kanban.lock.flock` timed out |

## Worked examples

**First use in a project (no `prefix=` yet) — confirm before proceeding:**
```bash
"$ROOT"/skills/kanban/scripts/kanban-id.sh --repo . next
# exit 2, stderr:
#   kanban: this project has no default prefix yet — confirmation required (never auto-picked).
#   kanban: prefixes on the board, most frequent first:
#     K        76 card(s), highest K-76
#     ...
#   kanban: confirm with:  kanban-id.sh --repo <repo> set-prefix <PREFIX>
# an agent should ASK THE USER here (AskUserQuestion, candidates as options),
# not guess — then:
"$ROOT"/skills/kanban/scripts/kanban-id.sh --repo . set-prefix K
"$ROOT"/skills/kanban/scripts/kanban-id.sh --repo . next   # K-77
```

**Create a task:**
```bash
"$ROOT"/skills/kanban/scripts/kanban-new.sh --title "Add rate limiter" --stage todo
# .claude/kanban/todo/AVF-43-add-rate-limiter.md
```

**Create an epic + 2 subtasks:**
```bash
S=skills/kanban/scripts
"$ROOT"/$S/kanban-new.sh --title "Billing rewrite" --epic --stage todo
# .claude/kanban/todo/EPIC-001-billing-rewrite.md (epic ID = EPIC-001)
"$ROOT"/$S/kanban-new.sh --title "DB schema" --sub EPIC-001
# .claude/kanban/todo/EPIC-001-01-db-schema.md
"$ROOT"/$S/kanban-new.sh --title "API CRUD" --sub EPIC-001
# .claude/kanban/todo/EPIC-001-02-api-crud.md
```

**Move a card and commit:**
```bash
MSG="$("$ROOT"/skills/kanban/scripts/kanban-move.sh AVF-43 progress)"
git commit -m "$MSG"   # task: start AVF-43 (todo→progress)
```

**Lint before finishing:**
```bash
"$ROOT"/skills/kanban/scripts/kanban-lint.sh || echo "fix findings above before moving on"
```
