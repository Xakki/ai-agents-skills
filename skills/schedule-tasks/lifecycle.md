# Kanban lifecycle (autonomous run contract)

The autonomous prompt walks one card through `todo → progress → test → ready`
in exactly **2 commits** per card (3 if a pre-task `wip:` is needed). The
final hop `ready → done` is the user's manual step.

## Commit shape per card

| #  | Commit subject                                       | Content                                                                                          |
|----|------------------------------------------------------|--------------------------------------------------------------------------------------------------|
| 0  | `wip: pre-task auto-commit before <ID>` *(optional)* | Whatever was dirty in the tree at run start                                                      |
| 1  | `task: <ID> impl` (or project's commit style)        | `git mv todo→progress` + all implementation + updated Execution Log                              |
| 2  | `task: review <ID> (progress→test→ready)`            | `git mv progress→test` + `git mv test→ready`, **no content edits**                               |

**Why bundle the `git mv todo→progress` into the impl commit:**
historically it was a separate "start" commit, but the chain never stops
*between* `todo→progress` and `impl` — the agent always proceeds — so the
extra commit was noise. The current shape keeps the kanban history grep-able
(`git log --diff-filter=R -- '.claude/kanban/*'` still shows every mv,
because the renames are part of commit 1's diff) without inflating the log.

**Why the final commit bundles two moves:**
`test/` is the review-in-progress slot, `ready/` is the post-review slot. By
the time the agent emits commit 2, review already passed — there's no value
in pausing at `test/`, so we collapse `progress→test→ready` into a single
review commit with no content edits.

The chain **never** writes anything that lands the card in `done/` — that's
the user's manual step (`ready→done`, after their final approval).

The implementation is **one bundled commit**, never many micro-commits per
subtask. Updates to the card's Execution Log live inside commit 1.

The `progress/` and `ready/` directories may not exist in fresh repos — the
agent runs `mkdir -p .claude/kanban/{progress,ready}` once before the first
transition that needs them.

## Outcome mapping (where the card lands → result code)

| Final location | `AUTO-RUN-RESULT` | Cause                                                              |
|----------------|--------------------|--------------------------------------------------------------------|
| `done/`        | `ok`               | User already approved while the run was finishing (rare race)      |
| `ready/`       | `ok`               | Implementation green, review green, awaiting user's `ready→done`   |
| `test/`        | `fail`             | Review found issues (Acceptance Criteria not met)                  |
| `progress/`    | `fail`             | qa (lint/test) red                                                  |
| `todo/`        | `skip`             | Card already moved, or suspicious-secret file blocked auto-commit  |
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

## Auto-commit at start (step 1 of prompt)

The autonomous run's first action is **NOT** refuse-on-dirty — it's
auto-commit any pending WIP with message `wip: pre-task auto-commit before
<ID>`. Rationale: leftover from previous chain link, new untracked todo cards,
or user's manual edits should never break the chain on a benign dirty tree.
`.gitignore` already protects `.env`, `bkp/**`, `_content/**` etc.

Hard skip: if `git status` surfaces an obviously sensitive untracked file that
*isn't* gitignored (`secrets.yml`, `dump.sql`, `*.pem`, `id_rsa`) — the agent
exits with `AUTO-RUN-RESULT: skip: ... suspicious untracked file ...` for
manual review.

## Forbidden in the prompt

- `git stash`, `git checkout -- .`, `git reset --hard`, `git clean`
- A standalone `task: start <ID> (todo→progress)` commit — that move belongs
  in commit 1 alongside the implementation
- Moving a card into `done/` (only the user does that, from `ready/`)
- Starting a card from `grooming/` (chain only consumes `todo/`)
- Mixing content edits with `git mv` in **commit 2** specifically (the
  green-path `progress→test→ready` review commit is two moves only — no
  Execution Log edits, no code changes). Fail-path commits (`task: qa failed`,
  `task: review found issues`) are allowed to bundle Execution Log edits
  (and, for review-fail, the `progress→test` mv) — that's the documented
  exception, since the chain is stopping for manual review anyway
- Splitting implementation into multiple commits — one bundled `task: impl`
  per card
- `--no-verify`
- `git push`, `gh pr create`, branch merges
