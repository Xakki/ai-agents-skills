# Kanban lifecycle (autonomous run contract)

The autonomous prompt walks one card through `todo → progress → test → ready`
on a dedicated `task/<NAME>` branch, merging to base on success. The
final hop `ready → done` is the user's manual step.

## Branch model

| Phase | Branch | What happens |
|-------|--------|--------------|
| Start | **base** | `git mv todo→progress` + commit; then `git switch -c "task/<NAME>"` |
| Impl / qa / review | `task/<NAME>` | all work + commits |
| Finalize (ok) | `task/<NAME>` → **base** | `git mv test→ready` + commit; `git switch base`; `git merge --no-ff --no-edit "task/<NAME>"`; `git branch -d "task/<NAME>"` |
| Park (any failure) | `task/<NAME>` | `wip(park): <NAME> (<REASON>)` via `park-task.sh`; branch stays; base stays clean |

## Commit shape per card

Happy path — 4+ commits on branch (except the start commit which lands on base):

| #  | Branch  | Commit subject                              | Content                                                                |
|----|---------|---------------------------------------------|------------------------------------------------------------------------|
| 1  | base    | `task: start <NAME> (todo→progress)`        | `git mv todo→progress` only                                            |
| 2+ | task/*  | `<scope>: <short description>` (one or more)| Code + Execution Log; scope: `api\|goclient\|ext\|infra\|db\|docs`     |
| 3  | task/*  | `task: review <NAME> (progress→test)`       | `git mv progress→test` only                                            |
| 4  | task/*  | `task: ready <NAME> (test→ready)`           | `git mv test→ready` only                                               |
| — merge — | base | (merge commit from `--no-ff`)            | lands all branch commits on base                                       |

Park-path commit (on `task/<NAME>` branch only — via `park-task.sh`):

| Reason         | Commit subject                                  |
|----------------|-------------------------------------------------|
| qa-fail        | `wip(park): <NAME> (qa-fail)`                   |
| review-fail    | `wip(park): <NAME> (review-fail)`               |
| blocker        | `wip(park): <NAME> (blocker)`                   |
| question       | `wip(park): <NAME> (question)`                  |
| merge-conflict | `wip(park): <NAME> (merge-conflict)`            |

The chain **never** writes anything that lands the card in `done/` — that's
the user's manual step (`ready→done`, after their final approval).

The `progress/`, `test/`, and `ready/` directories may not exist in fresh repos — the
agent runs `mkdir -p .claude/kanban/{progress,test,ready}` once before the first
transition that needs them.

## Outcome mapping (where the card lands → result code)

All three outcomes **advance the chain** (step 9 always runs). There is no terminal `fail` —
every failure becomes a `park`.

| Final location | `AUTO-RUN-RESULT` | Chain    | Cause                                                              |
|----------------|-------------------|----------|--------------------------------------------------------------------|
| `ready/` (merged to base) | `ok` | **advances** | Implementation green, review green, merged to base   |
| `progress/` or `test/` + branch `task/<NAME>` | `park` | **advances** | Task parked: qa-fail, review-fail, blocker, question, or merge-conflict |
| `todo/`        | `skip`            | **advances** | Step-2 sanity: card not in `todo/` (already moved or wrong stage) |
| `grooming/`    | `skip`            | **advances** | Card was parked for clarification — chain skips and moves on      |

The inner script uses this mapping as a **fallback** when the agent's final
`AUTO-RUN-RESULT:` line is missing or garbled — the kanban stage is the source
of truth.

## Implementation step (project-agnostic)

The agent reads the card and implements it. For subagent / test-command
selection it inspects the **host project's** `CLAUDE.md`:

- If the project documents named subagents (e.g. under a "Сабагенты" / "Subagents" / "Specialised agents" section), the agent picks the one whose description matches the touched module. If none match, it implements directly.
- For QA the agent runs the project's standard lint/test (commonly `make test` + `make lint`, otherwise whatever `CLAUDE.md` documents). If the project has no such command, the agent runs targeted tests for the touched files (e.g. `pytest <path>`, `npm test -- <pattern>`, `go test ./<pkg>`).
- The Execution Log section in the card is updated during implementation — those edits land in commit 1 alongside the code changes.

No project-specific agent names or skill names are hard-coded in the prompt.

## Next-task selection (for self-chain step)

Step 9 runs on **every** outcome (ok/park/skip) via `select-next-task.sh`. The script
picks one next card from `.claude/kanban/todo/` (NOT from `grooming/`):

1. **Skip blocked cards.** A card is **blocked** if it contains a `depends on` /
   `blocked by` / `зависит от` / `блокируется` line (case-insensitive) referencing
   a task ID that currently has an entry in `.parked/`. Blocked cards are skipped;
   the chain picks the next unblocked candidate.
2. **Related card first.** Among unblocked cards, prefer a card that:
   - shares an ID prefix with the just-finished card (e.g. both start `K-`, `STORY-`), OR
   - mentions the finished card's ID in its body.
   If multiple match, take the **lexicographically smallest filename**.
3. **Otherwise lexicographic.** Lex-smallest unblocked card in `todo/`.
4. **All blocked / empty** → `AUTO-RUN-NEXT: none`, do NOT call `at`.

The selection logic lives in `scripts/select-next-task.sh` (args: `<REPO> <PARKED_DIR> [<JUST_FINISHED_NAME>]`).
No exclusion lists, no roadmap parsing. To keep a card out of the chain: move it to `grooming/`.

## Chain stops cleanly when

- No eligible next card (`AUTO-RUN-NEXT: none`) → inner script removes
  `.chain-conditions` file as cleanup.
- Working tree (base) has **new** uncommitted paths at chain step (baseline-aware `comm -23`
  check — pre-existing dirt is fine). After ok (merge) or park (base stays clean) this
  should not apply; after skip (no branch created) also fine.
- `atd` is inactive (`systemctl is-active atd` ≠ `active`).
- All remaining `todo/` cards are blocked (each depends-on a currently-parked task).

A stopped chain is **never** auto-restarted — the user re-arms via
`/schedule-tasks`.

## Proceed on dirty; preserve uncommitted; never bulk-stage

A dirty working tree is **not a reason to stop**. Step 1 of the autonomous prompt
tells the agent: tree may be dirty — proceed normally.

Rules:
- **No stash, no reset, no clean.** Pre-existing uncommitted files must never be touched
  except when the task itself needs to edit them.
- **Explicit-path staging only.** Every `git add` and `git commit` must name
  exact paths (`git add <paths>` / `git commit -- <paths>` or plain `git commit`
  after a `git mv`). NEVER `git add -A`, `git add .`, `git add -u`, `git commit -a`.
- **End-of-run auto-commit** (usage stats append) uses the baseline snapshot
  (`$LOG_DIR/.baseline-dirty-<TS>`) to distinguish pre-existing dirt from new
  task changes; it stages only those new kanban `.md` paths explicitly.
- **Chain dirty-check** (step 9) compares the current dirty set against the
  baseline snapshot with `comm -23`; pre-existing dirt is ignored, only new
  uncommitted task changes stop the chain.

One exception: a `wip(park): <NAME> (<REASON>)` commit IS made
during escalation — but only on the isolated `task/<NAME>` branch (explicit-path
staging applies there too), never on base.

## Forbidden in the prompt

- `git add -A`, `git add .`, `git add -u`, `git commit -a` — always stage explicit paths only
- `git stash`, `git checkout -- .`, `git reset --hard`, `git clean`
- Bundling `task: start <NAME> (todo→progress)` with implementation — the
  start mv is always its OWN commit before any code changes (required)
- Moving a card into `done/` (only the user does that, from `ready/`)
- Starting a card from `grooming/` (chain only consumes `todo/`)
- Mixing content edits with `git mv` commits (commits 1, 3, 4 on happy path
  contain ONLY the kanban move — no Execution Log edits, no code changes).
- `--no-verify`
- `git push`, `gh pr create`, branch merges
- `AskUserQuestion` — the autonomous flow never blocks on a question; escalation parks instead
- WIP commits on the base branch — the `wip(park): ...` commit is the sole exception, and it
  is ONLY allowed on a `task/*` branch (never on base)
