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

## Autonomous-Run Commit Contract

Manual/orchestrated work uses the per-task branch model in `SKILL.md` (own
`task/<ID>` branch, sub-agents commit their zones; on OK move the card to
`done/`, verify the branch is clean, then squash-merge + rename to
`done/<orig>`), following the [git-flow](../git-flow/SKILL.md) core.

Autonomous (`schedule-tasks`) runs also use a `task/<ID>` branch but with their
own commit shape and merge/park mechanics — `schedule-tasks` owns that contract.
See `schedule-tasks/lifecycle.md` for its full commit table.
