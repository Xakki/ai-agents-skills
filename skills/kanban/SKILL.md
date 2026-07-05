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

User explicitly approves. Order matters — card first, merge last:

1. Move the card `ready/ → done/`.
2. Verify the task branch is clean (`git status --short` empty — everything
   committed, nothing stray left uncommitted).
3. Only then squash-merge the branch into the default branch (see Git Commits
   below).

Never done autonomously; never merge before the card is in `done/` and the
branch has been verified clean.

## Git Commits

Git mechanics follow the [git-flow](../git-flow/SKILL.md) core. Kanban's delta:
a task is worked **in its own branch**.

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
  `done/<orig-name>` (kept as an archive for optional later cleanup — do not
  delete immediately).
- Moving cards between stage dirs → [`git-move`](../git-move/SKILL.md).

See [reference.md](reference.md) for the autonomous-run commit contract.

## Stop Conditions

- Do NOT skip planning.
- Do NOT move to `done/` without explicit user approval.
- Do NOT start a card from `grooming/` — resolve open questions, move to `todo/` first.
- Do NOT silently resolve `grooming/` questions — ask the user; record in `**Decisions:**`.
- Do NOT move to `ready/` while tests are red.

## Правила делегирования задачи

1. **Один агент — одна зона.** Кросс-зональная задача: основной агент делает
   свою зону; общий контракт закреплён в отдельном skill (например,
   protocol/contract skill); смежные реализации делают свои агенты, читающие
   тот же skill.
2. **`security-auditor` — read-only**: выдаёт отчёт, код не пишет. Правки делает
   агент-имплементатор.
3. **`test-engineer` пишет тесты, не бизнес-логику.** Если тесту нужен новый
   эндпойнт/хук в коде → завести подзадачу в kanban и делегировать её
   агенту-имплементатору.
4. **Новый агент — только по явной необходимости.** Если задача укладывается в
   существующего агента — не плодить агентов.
