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

## Task Lifecycle

### 1. Create

- **Scope clear** (AC, files, approach all settled) → create from [task template](task-template.md) in `todo/`.
- **Open questions remain** → create in `grooming/`; list them in `**Open questions:**`.

### 1a. Groom (grooming/ → todo/)

Grooming is a **user consultation**, not autonomous execution. Surface choices; don't resolve them silently.

- Read the card's `**Open questions:**` and raise each with the user (options + trade-off + recommendation). Use `AskUserQuestion` for discrete choices (recommended first). Do not guess.
- If new ambiguities surface → append to `**Open questions:**` and raise them too.
- Record every resolution in `**Decisions:**` before moving to `todo/`. Remove `**Open questions:**` on transition.
- Only when **nothing ambiguous remains** (scope, acceptance, approach all settled) → move `grooming/ → todo/`.

See [reference.md](reference.md) for the full grooming protocol.

### 2. Start (todo → progress)

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

User explicitly approves and moves `ready/ → done/`. Never done autonomously.

## Git Commits

**Do not commit card movements separately.** Move cards with `git mv` (tracked) or plain `mv` (untracked) **without committing** — moves and edits stay in the working tree while the card progresses.

Make **one commit only, on successful completion** — when the card reaches `ready/`. It bundles the implementation, card edits, and all stage moves.

- Commit is made by the **orchestrator** (main thread); sub-agents do the work but never move cards or commit.
- Commit subject describes the completed work (e.g. `task: <ID> done`), not individual moves.
- Task fails or is abandoned before `ready/` → no commit.
- See [`git-move`](../git-move/SKILL.md) for tracked/untracked move mechanics.

See [reference.md](reference.md) for the autonomous-run commit contract.

## Stop Conditions

- Do NOT skip planning.
- Do NOT move to `done/` without explicit user approval.
- Do NOT start a card from `grooming/` — resolve open questions, move to `todo/` first.
- Do NOT silently resolve `grooming/` questions — ask the user; record in `**Decisions:**`.
- Do NOT move to `ready/` while tests are red.
- Sub-agents do NOT move cards or commit — orchestrator only.
