# Kanban lifecycle (autonomous run contract)

The autonomous prompt walks one card through `todo → progress → test → ready`
in exactly **4 commits** per card (happy path). The
final hop `ready → done` is the user's manual step.

## Commit shape per card

Happy path — 4 commits, each `git mv` in its own commit, content never mixed with moves:

| #  | Commit subject                              | Content                                                                |
|----|---------------------------------------------|------------------------------------------------------------------------|
| 1  | `task: start <NAME> (todo→progress)`        | `git mv todo→progress` only — no code, no Execution Log edits          |
| 2  | `<scope>: <short description>` (one or more)| Code + Execution Log update; scope: `api\|goclient\|ext\|infra\|db\|docs` |
| 3  | `task: review <NAME> (progress→test)`       | `git mv progress→test` only — no content edits                         |
| 4  | `task: ready <NAME> (test→ready)`           | `git mv test→ready` only — no content edits (green path only)          |

Fail-path commits (chain stops, card stays in current stage):

| Condition           | Commit subject                       |
|---------------------|--------------------------------------|
| qa-check red        | `task: <NAME> qa-check failed`       |
| review found issues | `task: <NAME> review found issues`   |

The chain **never** writes anything that lands the card in `done/` — that's
the user's manual step (`ready→done`, after their final approval).

The `progress/`, `test/`, and `ready/` directories may not exist in fresh repos — the
agent runs `mkdir -p .claude/kanban/{progress,test,ready}` once before the first
transition that needs them.

## Outcome mapping (where the card lands → result code)

| Final location | `AUTO-RUN-RESULT` | Cause                                                              |
|----------------|--------------------|--------------------------------------------------------------------|
| `done/`        | `ok`               | User already approved while the run was finishing (rare race)      |
| `ready/`       | `ok`               | Implementation green, review green, awaiting user's `ready→done`   |
| `test/`        | `fail`             | Review found issues (Acceptance Criteria not met)                  |
| `progress/`    | `fail`             | qa (lint/test) red                                                  |
| `todo/`        | `skip`             | Step-2 sanity: card not in `todo/` (already moved or wrong stage)  |
| `grooming/`    | `skip`             | Card was parked for clarification — chain refused to start it      |

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

Run **only** on a green outcome (card landed in `ready/`). The agent picks one
next card from `.claude/kanban/todo/` (NOT from `grooming/` — those cards are
parked because they need clarification, the autonomous run never touches them):

1. **Related card first.** Scan filenames + (cheaply) contents of `todo/*.md`
   for a card that:
   - shares an ID prefix with the just-finished card (e.g. both start `front-`, `K-`, `STORY-`, `2026-05-25-front-`), OR
   - mentions the finished card's ID in its "depends on" / "blocked by" / "related" / "Acceptance Criteria" sections.
   If multiple match, take the **lexicographically smallest filename**.
2. **Otherwise lexicographic.** `ls .claude/kanban/todo/ | sort | head -1`.
   Caveat: lex sort is digit-by-digit (`front-10` < `front-9`); zero-pad numeric
   segments in card filenames (`front-009`, `front-010`) if exact numeric order
   matters across decade boundaries.
3. **Empty** → no next card → print `AUTO-RUN-NEXT: none`, do NOT call `at`.

No exclusion lists, no roadmap parsing, no priority blocks. If the project
needs a card kept out of the chain, the user moves it to `grooming/` (parking)
or any non-`todo/` stage.

## Chain stops cleanly when

- Outcome was `fail` or `skip` (manual review needed).
- No eligible next card (`AUTO-RUN-NEXT: none`) → inner script removes
  `.chain-conditions` file as cleanup.
- Working tree is dirty at chain step (the previous card's edits weren't fully committed — manual review).
- `atd` is inactive (`systemctl is-active atd` ≠ `active`).

A stopped chain is **never** auto-restarted — the user re-arms via
`/schedule-tasks`.

## Refuse on dirty (step 1 of prompt)

The autonomous run's **first** action is a hard dirty-tree check:
`git status --porcelain`. If ANY modification (M/A/D/R/??) is present —
the agent sends tg-notify (s=warn, title `auto-run <NAME>: skip (dirty tree)`),
prints exactly:
```
AUTO-RUN-RESULT: skip: <NAME>: working tree dirty, manual intervention required
```
and exits immediately.

There is **no** `wip: pre-task auto-commit`; there is **no** stash; there is
**no** ignore list for "sensitive files". Any dirt → skip. The tree must be
clean before each run.

## Forbidden in the prompt

- `git stash`, `git checkout -- .`, `git reset --hard`, `git clean`
- Bundling `task: start <NAME> (todo→progress)` with implementation — the
  start mv is always its OWN commit before any code changes (required)
- Moving a card into `done/` (only the user does that, from `ready/`)
- Starting a card from `grooming/` (chain only consumes `todo/`)
- Mixing content edits with `git mv` commits (commits 1, 3, 4 on happy path
  contain ONLY the kanban move — no Execution Log edits, no code changes).
  Fail-path commits (`task: <NAME> qa-check failed`, `task: <NAME> review found issues`)
  may include Execution Log updates — that's the documented exception since
  the chain stops for manual review anyway.
- `--no-verify`
- `git push`, `gh pr create`, branch merges
