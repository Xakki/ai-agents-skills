# kanban — reference

Read this for the full grooming protocol and the autonomous-run commit contract.

## Full Grooming Protocol

Working a `grooming/` card is a **consultation with the user**, not autonomous execution. Your job is to surface choices and resolve ambiguity *together* — never to silently pick an answer.

- Read the card and its `**Open questions:**`.
- For every open question, doubtful point, or place where **more than one approach is viable** → ask the user. Present options + trade-off + recommendation. Use `AskUserQuestion` for discrete choices (recommended option first). Do not guess.
- If new ambiguities or doubts surface while grooming → append them to `**Open questions:**` and raise them too. Better to over-ask than to bake in a wrong assumption.
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
  parallel and where one hard-blocks the next.
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
`todo/ → progress/ → test/ → ready/` normally. It stops at `ready/`:
- Do NOT move a subtask to `done/`. `done/` for a subtask is granted only when
  the user approves the parent epic.
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
what to verify (concrete commands / URLs / expected output). The user moves
`ready/ → done/`; then the subtask cards follow to `done/`, the branch is
verified clean, squash-merged, and renamed `done/<ID>` (strip the `epic/`
prefix — archive is `done/<ID>`, NOT `done/epic/<ID>`).

## Autonomous-Run Commit Contract

Manual/orchestrated work uses the per-task branch model in `SKILL.md` (own
`task/<ID>` branch, sub-agents commit their zones; on OK move the card to
`done/`, verify the branch is clean, then squash-merge + rename to
`done/<ID>` — strip the `task/` prefix, archive is `done/<ID>` not
`done/task/<ID>`), following the [git-flow](../git-flow/SKILL.md) core.

Autonomous (`schedule-tasks`) runs also use a `task/<ID>` branch but with their
own commit shape and merge/park mechanics — `schedule-tasks` owns that contract.
See `schedule-tasks/lifecycle.md` for its full commit table.
