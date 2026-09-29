---
name: kanban
description: Use when managing tasks — creating, grooming/refining draft tasks, starting, completing, or reviewing task status.
---

## Stages

| Stage    | Canonical path              | Description                                                |
|----------|-----------------------------|------------------------------------------------------------|
| Grooming | `.agents/kanban/grooming/`  | Draft tasks with open questions / unresolved scope         |
| Todo     | `.agents/kanban/todo/`      | Refined tasks ready to start                               |
| Progress | `.agents/kanban/progress/`  | Currently being worked on                                  |
| Test     | `.agents/kanban/test/`      | Implementation handed off; review/QA in progress           |
| Ready    | `.agents/kanban/ready/`     | Auto-review passed; awaiting authorized finalization       |
| Done     | `.agents/kanban/done/`      | Successfully completed work                                |
| Freeze   | `.agents/kanban/freeze/`    | Temporarily paused work awaiting its recorded return condition |
| Closed   | `.agents/kanban/closed/`    | Cancelled or superseded work; terminal archive             |

Lifecycle: `grooming → todo → progress → test → ready → done`.

New boards default to `.agents/kanban`. Existing `.claude/kanban` boards remain
supported. Aliases resolving to the same physical directory are one board; if
both paths resolve to different boards, helpers fail closed. The counter file
is `kanban.lock` beside the resolved board root (for example,
`.agents/kanban.lock` or the legacy `.claude/kanban.lock`). Conflicting lock
files also fail closed.

`freeze/` is a side state: enter from `grooming/`, `todo/`, `progress/`, `test/`,
or `ready/`; resume the same card only to `todo/` or `progress/` with
`--resume`. Record the pause reason and return condition in `**Decisions:**`.
`closed/` records cancellation/supersession, not successful completion; entering
it from any nonterminal stage, including `freeze/`, requires `--approved`.
`closed/` is terminal even with `--force`; future work gets a new linked card.
Both stages participate in board-wide ID uniqueness checks.

`grooming/` and `ready/` are agent-boundary stages: autonomous runs never enter
`grooming/`. The narrow `schedule-tasks` merge-at-ready exception permits merging
in-scope code after green QA and independent review while the card remains in
`ready/`; it never moves that card to `done/`. Any automated `ready/ → done/`
transition must independently satisfy the authorization rules in Done below; the
scheduler scope manifest does not authorize it.

## IDs & Prefix

Every card carries `<PREFIX>-<NUM>` or a legacy letter-suffixed ID
`<PREFIX>-<NUM><LETTER>` (epic subtasks: `<PREFIX>-<NUM>-<NN>`, see Epics
below). Counters live in the committed `kanban.lock` beside the resolved board
root; allocation uses a companion `flock` marker and reconciles against cards
actually on the board on every allocation — a stale counter after a merge
can't hand out a duplicate ID. The ID parser preserves the optional letter, so
`K-094a` and `K-094b` are distinct IDs; slug words such as `css-grid` are not
prefix candidates.
**First use in a project (no `prefix=` yet) is a confirmation, never a
guess.** `kanban-id.sh next`/`prefix` exits 2 with the board's candidate
prefixes (existing board cards win by count if any, else a dir-name-derived
one) — on that exit, **ask the user** which to use (`AskUserQuestion`,
candidates as options, recommended one first) and then run
`kanban-id.sh set-prefix <PREFIX>` to confirm it; don't auto-pick and don't
retry silently. Full mechanics, lock format, prefix registry →
[scripts.md](scripts.md).

The adjacent `.flock` file coordinates only processes that open the same
resolved lock file. Separate Git worktrees have separate tracked counters and
lock markers; until a shared allocator exists, one canonical board owner must
allocate IDs and perform lifecycle moves from the canonical checkout. Task
worktrees do not allocate IDs or mutate board stages.

## Scripts

Set `ROOT="${AI_AGENTS_SKILLS_ROOT:-${CLAUDE_PLUGIN_ROOT:-${PLUGIN_ROOT:-${CURSOR_PLUGIN_ROOT:-}}}}"` and
`S="$ROOT/skills/kanban/scripts"`, then invoke every script below as `"$S"/<name>` — never by bare name
(optional leading `--repo <path>`, default git toplevel):

| Script | Purpose | Key flag |
|---|---|---|
| `"$S"/kanban-id.sh` | allocate/inspect IDs (`next`\|`epic`\|`sub`\|`peek`\|`prefix`) | `sub <EPIC-ID>` |
| `"$S"/kanban-new.sh` | allocate ID + render template + stage card | `--epic`\|`--sub <EPIC-ID>` |
| `"$S"/kanban-move.sh` | validated stage transition (wraps [git-move](../git-move/SKILL.md)) | `--approved` for `→done`/`→closed`; `--resume` from `freeze/` |
| `"$S"/kanban-status.sh` | board overview, subtasks grouped under their epic | `--epic ID` |
| `"$S"/kanban-lint.sh` | card validation (shape, template, dupes, counter drift) | — |

Full CLI, flags, exit codes, worked examples → [scripts.md](scripts.md). Manual
fallback (hand-written card using the resolved board's adjacent `kanban.lock` +
[git-move](../git-move/SKILL.md) directly) still works if a script is
unavailable.

## Task Lifecycle

### 1. Create

- **Default:** `"$S"/kanban-new.sh --title "…" --stage todo` (or `--stage grooming` when scope isn't settled) — allocates the ID, renders [task template](task-template.md), stages the card, prints its path.
- **Manual fallback:** allocate the next ID by hand against the lock beside the resolved board root, fill in [task template](task-template.md), `git add`.
- **Scope clear** (AC, files, approach all settled) → `todo/`.
- **Open questions remain** → `grooming/`; list them in `**Open questions:**`.

#### Side-found / user-suggested fixes

When a bug/err is found OR the user suggests a fix:

1. **Dedupe first.** Scan `grooming/` and `todo/` for an existing card on the same topic. If found → do NOT create another; apply triage (step 2) against that card — if fix-now criteria hold → fix now and log/note on it; else leave work on that card (groom later).
2. **Triage — fix now vs file grooming:**
   - **Fix now** when ANY of: in-scope of the active task; OR cplx ≤ 3/10; OR standard-subagent-sized.
     - Active task → log on the card (Execution Log / `**Decisions:**`).
     - No active task → mention in the commit msg.
   - **File a new `grooming/` card** only when ALL hold: (oos of active task OR no active task) AND cplx > 3/10 AND not standard-subagent-sized.
   - **Append to the nits dump** when the finding is oos of the active task AND is
     NOT being taken into work now AND is too small to deserve its own card. This
     is the catch-all: a finding is never dropped silently — it is fixed, carded,
     or dumped.
3. **Wrap-up report.** On task completion (hand-off / ready), surface to the user a short list of: (a) side-filed grooming cards created during the work, (b) en-route fixes that were done (no new card), (c) nits appended to the dump.

#### Nits dump — `.agents/kanban/grooming/TODO.md`

Running scratch list of small out-of-scope findings picked up in passing. Create
the file if absent.

- **One line per finding:** `<date> — <file>:<line> — what's wrong`, grouped
  under a dated heading `## <YYYY-MM-DD> — from <what you were doing>`.
- **Small findings only.** Anything substantial gets its own `grooming/` card
  instead. Mark a borderline entry `CANDIDATE FOR ITS OWN CARD` so the next
  grooming pass promotes it rather than re-triaging it from scratch.
- **Include the evidence**, not just the symptom: how it was confirmed, and what
  it was confirmed NOT to be (a ruled-out cause is the expensive part to redo).
- **Promoted to a card → DELETE the line.** Leave no back-pointer: the card is
  the single source, and a pointer stub only clutters the dump and goes stale.
  The file holds ONLY what has no card yet. Same when a nit gets fixed in
  passing — delete it, don't annotate it as done.
- **Project-local scratch.** Projects commonly git-exclude this file — follow the
  project's convention, and never slip it into a task branch or PR.

### 1a. Groom (grooming/ → todo/)

Grooming is a **user consultation**, not autonomous execution. Surface choices; don't resolve them silently.

- Read the card's `**Open questions:**` and raise each with the user (options + trade-off + recommendation). Use `AskUserQuestion` for discrete choices (recommended first). Do not guess.
- If new ambiguities surface → append to `**Open questions:**` and raise them too.
- Record every resolution in `**Decisions:**` before moving to `todo/`. Remove `**Open questions:**` on transition.
- Only when **nothing ambiguous remains** (scope, acceptance, approach all settled) → move `grooming/ → todo/`.

See [reference.md](reference.md) for the full grooming protocol.

### 2. Start (todo → progress)

- **Brief the user first (interactive starts).** Before moving the card to
  `progress/`, post a short, plain-language task briefing to the user **in the
  user's language**: what the task does and why, the acceptance criteria, the
  planned approach, and which files/areas it touches. It's a read-back so the
  user can catch a wrong card or misread scope before work starts — keep it
  concise and explained, don't dump the raw card. Skip only on autonomous/
  unattended runs (no user present, e.g. schedule-tasks).
- **From file**: move `.agents/kanban/todo/<task>.md` → `progress/`.
- **From description**: create from [task template](task-template.md) in `todo/`, then move to `progress/` (only if scope is clear).

### 3. Implement (progress/)

- Read task file. Plan via `TaskCreate` (atomic subtasks, 1-5 iterations each); track with `TaskUpdate`.
- Add "Execution Log" section to the task file; update after each significant step.

### 4. Test (progress → test)

Move card to `test/`. Run QA checks (lint/tests per project `CLAUDE.md`).

### 5. Ready (test → ready)

Auto-review passed + AC met + tests green → move to `ready/`. If review finds issues → stay in `test/`.

### 6. Done (ready → done) — authorized finalization

Authorization is exactly one of: `explicit user approval at hand-off`; or, only
for one named EPIC and its approved child cards, `recorded EPIC-scoped upfront
autonomous authorization`. The latter never authorizes push, a later EPIC, scope
expansion, or bypassing tests/review. Normal/manual finalization order is card
first, merge last:

1. Move the card `ready/ → done/` (`kanban-move.sh <ID> done --approved` or git-move manually).
2. Verify the task branch is clean (`git status --short` empty — everything
   committed, nothing stray left uncommitted).
3. Only then squash-merge the branch into the default branch (see Git Commits
   below).

Outside an EPIC with recorded EPIC-scoped upfront autonomous authorization,
`ready/ → done/` requires explicit user approval at hand-off. For normal/manual
work, never merge before the card is in `done/` and the branch has been verified
clean.

**Narrow `schedule-tasks` exception:** a task may be squash-merged from `ready/`
while its card remains in `ready/` only when a valid hash-verified scope manifest
lists that exact card, the scope was approved before scheduling, and QA plus an
independent review passed. This exception permits merge-at-ready and chaining only
inside the manifest. It never moves the card to `done/`, authorizes push/deploy,
or overrides project-local rules. The user still performs `ready/ → done/` later.

### Freeze and closed

- A card may enter `freeze/` from `grooming/`, `todo/`, `progress/`, `test/`, or
  `ready/`. Add its pause reason and return condition to `**Decisions:**`; lint
  does not require new headings for these notes.
- Resume from `freeze/` to `todo/` or `progress/` only with
  `kanban-move.sh <ID> <stage> --resume`. `--force` cannot bypass this rule.
- Move a cancelled or superseded card to `closed/` only with
  `kanban-move.sh <ID> closed --approved`. This flag is a caller attestation;
  the caller must already have explicit user authorization to cancel the work.
  A card in `closed/` cannot be moved out, even with `--force`; create a new
  linked card for future work. A successfully completed `done/` card cannot be
  reclassified as cancelled.
- `done/`, `freeze/`, and `closed/` skip active-card content-completeness lint,
  but all exact card IDs across all stages must be unique.

## Epics

An **epic** is a card whose body lists ordered subtask cards. Subtasks are normal
cards; the epic is their parent and their integration point.

- **Naming — reserved shared ID.** The epic always gets an `EPIC-<NUM>` ID
  (`kanban-new.sh --epic`), independently of the project's regular task prefix;
  every subtask reuses that SAME ID plus a 2-digit suffix in execution order
  (`kanban-new.sh --sub <EPIC-ID>`): e.g. `EPIC-042-billing-epic.md`,
  `EPIC-042-01-db-schema.md`, `EPIC-042-02-api-crud.md`… Regular cards retain
  their `<PREFIX>-<NUM>` IDs.
  Epic and subtasks share the leading `^[A-Za-z][A-Za-z0-9]*-[0-9]+` ID token —
  `schedule-tasks` groups them as one chain (related-card-first selection,
  dependency blocking) and the byobu window name stays inside its 10-char cap.
- **Start.** Epic card → `progress/`. Create ONE branch `epic/<ID>` for the whole
  epic; every subtask is implemented in that branch, not in its own `task/<ID>`.
- **Subtasks.** Work them in the listed order. Each finished subtask card moves
  `progress/ → test/ → ready/` as usual. A subtask **never** reaches `done/` on
  its own — the epic gates that.
- **Integration.** When the last subtask reaches `ready/`: restart the project,
  refresh all data (re-run imports/migrations), and run the full test suite.
- **Hand-off.** Only then move the epic card to `ready/` and obtain explicit user
  approval at hand-off or recorded EPIC-scoped upfront autonomous authorization.
  Move the parent to `done/`, then its subtasks as the script permits; verify
  `epic/<ID>` is clean; squash-merge once; then rename the archive to `done/<ID>`
  (`git branch -m epic/<ID> done/<ID>`). Never delete that archive branch.

See [reference.md](reference.md) for the full epic protocol.

## Git Commits

Git mechanics follow the [git-flow](../git-flow/SKILL.md) core. Kanban's delta:
a task is worked **in its own branch** (an epic's subtasks share the epic branch
— see Epics above).

- **Branch.** By default work the task in a NEW branch `task/<ID>` (aligns with
  schedule-tasks). Create it at start.
- **Sub-agents commit.** Each sub-agent commits its OWN zone's work into that
  branch (git-flow format + `Agent: <zone>` footer).
- **Orchestrator finalizes.** On task completion the orchestrator makes a
  wrap-up commit on the branch (adding its own remaining bits).
- **Merge on OK — card and clean-check before merge.** Review OK → move the
  card to `done/` and verify the branch is clean (`git status --short` empty)
  *before* touching the default branch. Only then **squash-merge** the branch
  into the default branch as ONE commit, then **rename** the branch to
  `done/<ID>` — strip the `task/` prefix (`git branch -m task/<ID> done/<ID>`);
  the archive is `done/<ID>`, NOT `done/task/<ID>`. Kept as an archive for
  optional later cleanup — do not delete immediately.
- Moving cards between stage dirs → `kanban-move.sh` (wraps [git-move](../git-move/SKILL.md), validates the transition); manual fallback → `git-move` directly.

See [reference.md](reference.md) for the autonomous-run commit contract.

## Stop Conditions

- Do NOT skip planning.
- Do NOT move to `done/` without explicit user approval at hand-off or recorded
  EPIC-scoped upfront autonomous authorization.
- Do NOT start a card from `grooming/` — resolve open questions, move to `todo/` first.
- Do NOT silently resolve `grooming/` questions — ask the user; record in `**Decisions:**`.
- Do NOT move to `ready/` while tests are red.
- Do NOT file a new card for an en-route/user-suggested fix until `grooming/`+`todo/` are scanned for a duplicate.
- Do NOT file when the fix is in-scope OR cplx ≤ 3/10 OR standard-subagent-sized — fix now; log on card or commit msg if no active task.
- Do NOT drop an oos finding silently — fix it, card it, or append it to `.agents/kanban/grooming/TODO.md`.
- Do NOT commit the nits dump into a task branch/PR when the project git-excludes it.
- MUST surface wrap-up list (side-filed grooming + en-route fixes + dumped nits) on hand-off/ready.

## Task Delegation Rules

1. **One agent — one zone.** Cross-zone task: the main agent does its own zone;
   the shared contract lives in a separate skill (e.g. a protocol/contract
   skill); adjacent implementations are done by their own agents reading that
   same skill.
2. **`security-auditor` — read-only**: emits a report, writes no code. Fixes are
   done by an implementer agent.
3. **`test-engineer` writes tests, not business logic.** If a test needs a new
   endpoint/hook in the code → file a subtask in kanban and delegate it to an
   implementer agent.
4. **New agent — only when clearly needed.** If the task fits an existing
   agent — don't spawn extra agents.
