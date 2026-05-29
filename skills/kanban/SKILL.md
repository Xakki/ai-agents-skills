---
name: kanban
description: Use when managing tasks — creating, starting, completing, or reviewing task status.
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

`grooming/` and `ready/` are new stages — the autonomous run (`schedule-tasks`)
never enters `grooming/` and never leaves a card past `ready/`. Only the user
moves `ready/ → done/`.

> **Note on commit shape during autonomous runs:** the `schedule-tasks` skill
> collapses `progress → test → ready` into a single review commit (and bundles
> `todo → progress` into the impl commit) — that's the autonomous-run contract,
> not a deviation from these stages. See `schedule-tasks/lifecycle.md` for the
> commit table. For manual work, transition stage by stage as you prefer.

## Task Lifecycle

### 1. Planning a new task

- **If scope is clear** (Acceptance Criteria, files, approach all settled) →
  create new file from [task template](task-template.md) in `todo/`.
- **If there are open questions** (unclear acceptance, missing decision,
  conflicting conventions, dependency on another card) → create in
  `grooming/`. List the open questions explicitly in a `**Open questions:**`
  section. Only after the questions are resolved → move to `todo/`.

`grooming/` is a parking lot for "we noticed this but haven't decided how to
solve it yet". Do **not** start autonomously from `grooming/` — those cards
are by definition not ready to execute.

### 2. Start (todo → progress)

- **From file**: Move `.claude/kanban/todo/<task>.md` → `progress/`
- **From description**: Create new file from [task template](task-template.md)
  in `todo/`, then move to `progress/` (only if scope is clear).

### 3. Plan & implement (in `progress/`)

- Read task file.
- Create sequential sub-task plan via `TaskCreate` (track progress with `TaskUpdate`).
- Add "Execution Log" section to task file.
- Update log after each significant sub-task completion.

### 4. Test (progress → test)

- Move task file to `test/`.
- Run relevant QA checks (lint/tests per project `CLAUDE.md`).
- User tests, or agent runs review/tests.

### 5. Ready for approval (test → ready)

- When auto-review passes (Acceptance Criteria met, tests green) → move to
  `ready/`. Card is now waiting for the user's final OK.
- If review finds issues → card **stays in `test/`**; do not move to `ready/`.

### 6. Done (ready → done) — user only

- The user explicitly approves and moves the card from `ready/` → `done/`.
- Autonomous runs never touch this transition (the kanban contract is "don't
  declare done without user approval").

## Guidance

- Break complex tasks into atomic subtasks (1-5 iterations each).
- Update task file with progress, decisions, roadblocks.
- Cards in `grooming/` need clarification, not execution — surface their open
  questions to the user when the topic comes up.

## Stop Conditions

- Do NOT skip planning phase.
- Do NOT move to `done/` without explicit user approval.
- Do NOT start a card directly from `grooming/` — clarify and move to `todo/` first.
- Do NOT move to `ready/` while review/tests are red.
