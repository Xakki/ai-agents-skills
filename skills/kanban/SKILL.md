---
name: kanban
description: Use when managing tasks — creating, grooming/refining draft tasks, starting, completing, or reviewing task status.
---

## Stages

| Stage    | Path                       | Description                                                |
|----------|----------------------------|------------------------------------------------------------|
| Grooming | `.claude/kanban/grooming/` | Draft tasks with open questions / unresolved scope         |
| Todo     | `.claude/kanban/todo/`     | Refined tasks ready to start                               |
| Progress | `.claude/kanban/progress/` | Currently being worked on                                  |
| Test     | `.claude/kanban/test/`     | Implementation handed off; review/QA in progress           |
| Ready    | `.claude/kanban/ready/`    | Auto-review passed; awaiting user's final approval         |
| Done     | `.claude/kanban/done/`     | Approved by user                                           |

Lifecycle: `grooming → todo → progress → test → ready → done`.

`grooming/` and `ready/` are agent-boundary stages: autonomous runs never enter `grooming/`
and never advance past `ready/`. Only the user moves `ready/ → done/`.

## IDs & Prefix

Every card carries `<PREFIX>-<NUM>` (epic subtasks: `<PREFIX>-<NUM>-<NN>`, see
Epics below). Counters live in `<repo>/.claude/kanban.lock` (git-committed,
`flock`-guarded, reconciled against cards actually on the board on every
allocation — a stale counter after a merge can't hand out a duplicate ID).
**First use in a project (no `prefix=` yet) is a confirmation, never a
guess.** `kanban-id.sh next`/`prefix` exits 2 with the board's candidate
prefixes (existing board cards win by count if any, else a dir-name-derived
one) — on that exit, **ask the user** which to use (`AskUserQuestion`,
candidates as options, recommended one first) and then run
`kanban-id.sh set-prefix <PREFIX>` to confirm it; don't auto-pick and don't
retry silently. Full mechanics, lock format, prefix registry →
[scripts.md](scripts.md).

## Scripts

Set `ROOT="${AI_AGENTS_SKILLS_ROOT:-${CLAUDE_PLUGIN_ROOT:-${PLUGIN_ROOT:-${CURSOR_PLUGIN_ROOT:-}}}}"`, then invoke as `"$ROOT"/skills/kanban/scripts/<name>`
(optional leading `--repo <path>`, default git toplevel):

| Script | Purpose | Key flag |
|---|---|---|
| `kanban-id.sh` | allocate/inspect IDs (`next`\|`epic`\|`sub`\|`peek`\|`prefix`) | `sub <EPIC-ID>` |
| `kanban-new.sh` | allocate ID + render template + stage card | `--epic`\|`--sub <EPIC-ID>` |
| `kanban-move.sh` | validated stage transition (wraps [git-move](../git-move/SKILL.md)) | `--approved` (required for `→done`) |
| `kanban-status.sh` | board overview, subtasks grouped under their epic | `--epic ID` |
| `kanban-lint.sh` | card validation (shape, template, dupes, counter drift) | — |

Full CLI, flags, exit codes, worked examples → [scripts.md](scripts.md). Manual
fallback (hand-written card + [git-move](../git-move/SKILL.md) directly) still
works if a script is unavailable.

## Task Lifecycle

### 1. Create

- **Default:** `"$ROOT"/skills/kanban/scripts/kanban-new.sh --title "…" --stage todo` (or `--stage grooming` when scope isn't settled) — allocates the ID, renders [task template](task-template.md), stages the card, prints its path.
- **Manual fallback:** allocate the next ID by hand against `.claude/kanban.lock`, fill in [task template](task-template.md), `git add`.
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

#### Nits dump — `.claude/kanban/grooming/TODO.md`

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
- **From file**: move `.claude/kanban/todo/<task>.md` → `progress/`.
- **From description**: create from [task template](task-template.md) in `todo/`, then move to `progress/` (only if scope is clear).

### 3. Implement (progress/)

- Read task file. Plan via `TaskCreate` (atomic subtasks, 1-5 iterations each); track with `TaskUpdate`.
- Add "Execution Log" section to the task file; update after each significant step.

### 4. Test (progress → test)

Move card to `test/`. Run QA checks (lint/tests per project `CLAUDE.md`).

### 5. Ready (test → ready)

Auto-review passed + AC met + tests green → move to `ready/`. If review finds issues → stay in `test/`.

### 6. Done (ready → done) — user only

User explicitly approves. Order matters — card first, merge last:

1. Move the card `ready/ → done/` (`kanban-move.sh <ID> done --approved` or git-move manually).
2. Verify the task branch is clean (`git status --short` empty — everything
   committed, nothing stray left uncommitted).
3. Only then squash-merge the branch into the default branch (see Git Commits
   below).

Never done autonomously; never merge before the card is in `done/` and the
branch has been verified clean.

## Epics

An **epic** is a card whose body lists ordered subtask cards. Subtasks are normal
cards; the epic is their parent and their integration point.

- **Naming — shared ID.** The epic gets a normal `<PREFIX>-<NUM>` ID
  (`kanban-new.sh --epic`); every subtask reuses that SAME ID plus a 2-digit
  suffix in execution order (`kanban-new.sh --sub <EPIC-ID>`): e.g.
  `K-042-billing-epic.md`, `K-042-01-db-schema.md`, `K-042-02-api-crud.md`…
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
- **Hand-off.** Only then move the epic card to `ready/` and ask the user to
  verify. The user approves the epic; its subtasks follow it to `done/`.

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
- Do NOT move to `done/` without explicit user approval.
- Do NOT start a card from `grooming/` — resolve open questions, move to `todo/` first.
- Do NOT silently resolve `grooming/` questions — ask the user; record in `**Decisions:**`.
- Do NOT move to `ready/` while tests are red.
- Do NOT file a new card for an en-route/user-suggested fix until `grooming/`+`todo/` are scanned for a duplicate.
- Do NOT file when the fix is in-scope OR cplx ≤ 3/10 OR standard-subagent-sized — fix now; log on card or commit msg if no active task.
- Do NOT drop an oos finding silently — fix it, card it, or append it to `.claude/kanban/grooming/TODO.md`.
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
