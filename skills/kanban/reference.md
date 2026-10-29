# kanban — reference

Read this for the full grooming protocol and the autonomous-run commit contract.

## Full Grooming Protocol

Working a `grooming/` card is a **consultation with the user**, not autonomous execution. Your job is to surface choices and resolve ambiguity *together* — never to silently pick an answer.

- Read the card and its `**Open questions:**`.
- Resolve routine decisions using the existing user instructions and project policy. Ask through an available runtime interface when a material preference or required authorization is missing; present options, trade-offs and a recommendation when helpful.
- Record new unresolved material questions on the card, and continue independent work where authorized. Never infer a missing grant.
- **Record every resolution on the card before it leaves `grooming/`.** Fold each answer into `**Decisions:**` (and AC / Recommendation as relevant). `**Open questions:**` is removed on `grooming → todo` — the rationale must survive in `**Decisions:**` or it's lost.
- When a parked `grooming/` topic comes up in conversation, proactively surface that card's open questions instead of letting it sit silent.
- Only when **nothing ambiguous remains** — scope, acceptance criteria, and approach all settled — finalize the card and move `grooming/ → todo/`.

## Full Epic Protocol

An epic groups subtasks that must land together. It exists when the work spans
several cards that share a schema, a contract, or a migration — shipping them
one at a time would leave the project in a broken intermediate state.

**Epic card body** must carry, beyond the normal template:
- `**Subtasks:**` — an ordered list of subtask IDs with a one-line purpose each.
  Order is execution order; note explicitly where two subtasks may run in
  parallel and where one hard-blocks the next. Parallel work is allowed only
  when dependencies permit it and the declared zones/allowed paths do not overlap.
- `**Integration checklist:**` — what must pass before the epic leaves `progress/`.

**Branch.** One branch `epic/<ID>` for the entire epic, created when the epic
card enters `progress/`. Subtasks do NOT get their own branches — this is the
deliberate exception to the per-task branch rule in `SKILL.md`. Sub-agents commit
their zone's work into the epic branch (git-flow format + `Agent: <zone>` footer).

**Scripts.** `kanban-new.sh --epic` allocates the epic's reserved `EPIC-<NUM>`
ID (independent of the regular task prefix) and renders its card; each subtask
card is then created with
`kanban-new.sh --sub <EPIC-ID>` (or `kanban-id.sh sub <EPIC-ID>` to just get the
next `NN`), which reuses the epic's ID plus a 2-digit suffix — see naming in
`SKILL.md`. `kanban-move.sh` enforces the `done/` gate mechanically: a subtask
move to `done/` is rejected until its epic is already in `done/`. Full CLI →
[scripts.md](scripts.md).

**Subtask flow inside an epic.** Each subtask card walks
`todo/ → progress/ → test/ → ready/` normally. `ready/` is its evidence
checkpoint; after the parent reaches `done/`, continue the child's finalization
when action-specific authorization covers it:
- Do NOT move a subtask to `done/` before its parent is `done/`. A valid action-
  specific authorization must cover the parent and child transitions; an
  applicable recorded profile/agent authorization is sufficient.
- Do NOT merge the epic branch when a subtask finishes. The branch merges once,
  after the epic is approved.
- If a subtask surfaces a new open question, park it in `grooming/` and raise it
  with the user — an epic in flight does not license silent decisions.

**Integration gate** (epic still in `progress/`, all subtasks in `ready/`):
1. Restart the project from a clean state (rebuild image / recreate containers).
2. Refresh all data — re-run migrations and every data import the epic touched.
3. Run the full quality gate (lint, tests, coverage, build) — not just the
   subset each subtask ran.
4. Any red → the epic stays in `progress/`; fix in the epic branch or open a new
   subtask. Never advance an epic on a red suite.

**Hand-off.** Green gate → move the epic card to `ready/` and tell the user
what to verify (concrete commands / URLs / expected output). `ready` is a checkpoint, not a compulsory human stop. Continue with each action
when valid action-specific authorization covers the target and all gates pass;
this includes explicit user approval at hand-off, recorded EPIC-scoped upfront
autonomous authorization, other recorded upfront task/workflow authorization,
or recorded profile/agent authorization. Record source, executor,
actions, limits, and results. A `done` grant alone does not grant push, later-EPIC
startup, scope expansion, or a test/review bypass. The exact order is:
parent `ready → done`, eligible subtasks to `done`, verify `epic/<ID>` clean,
then perform one squash merge only when separately authorized. Verify the base
commit and card locations; rename with `git branch -m epic/<ID> done/<ID>` only
after the successful, verified merge. If merge is missing or blocked, retain
the epic branch and report that the cards are not on the canonical base. Keep a
merged archive; do not delete it.

## Autonomous-Run Commit Contract

Manual/orchestrated work uses the per-task branch model in `SKILL.md` (own
`task/<ID>` branch, sub-agents commit their zones; on OK move the card to
`done/` only when authorized, verify the branch is clean, then squash-merge
only when separately authorized and rename only after the merge is verified to
`done/<ID>` — strip the `task/` prefix, archive is `done/<ID>` not
`done/task/<ID>`), following the [git-flow](../git-flow/SKILL.md) core.

Autonomous (`schedule-tasks`) runs also use a `task/<ID>` branch but with their
own commit shape and park mechanics. A valid, user-approved scope manifest is a
narrow exception: after green QA and independent review, an in-scope task may be
merged while its card remains in `ready/`. It never authorizes `done/`, push, or
deploy; the user moves the card to `done/` separately. See
`schedule-tasks/lifecycle.md` for the full contract.
