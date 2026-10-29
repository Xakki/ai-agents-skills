---
name: kanban-grooming-validation
description: Validate groomed Kanban cards, decisions, dependencies, and scoped changes.
license: MIT
---

# Kanban grooming validation

Use to validate a planning or grooming change without implying implementation acceptance.

1. Inspect the authorized board, relevant active and historical cards, decisions, and repository baseline if applicable. Check for exact, split, completed, and scope-overlapping duplicates before allocating an ID through the supported mechanism.
2. Check each card against the actual project template and owner decisions: scope, exclusions, dependencies, acceptance, verification, and unresolved questions must agree. Check reciprocal parent/child references and retain historical decisions without presenting them as current. A partial owner answer resolves only its approved portion; preserve remaining open decisions and gates. Verify named companion paths exist before editing them.
3. Use the project's canonical board validator on each changed card and verify the number of cards actually checked; use its supported exact path or basename rather than assuming short IDs resolve. Distinguish excluded stages, nonzero warnings, pre-existing board-wide failures, and checks not run. Inspect new or ignored files as well as tracked diffs. After an authorized move verify the actual destination and any maintained status field agree.
4. Report planning readiness separately from implementation, runtime, and production acceptance. Resolve only in-scope defects; do not create a commit, change unrelated cards, or widen the lifecycle scope without the applicable authorization.

Do not advance a grooming card with unresolved questions. If the user explicitly authorizes a bounded start while external evidence remains pending, record the authorized boundary and remaining closure gates without claiming external validation or expanding authority. If a helper staged an initial template or move before a substantive edit, inspect cached and working content separately and stage only the final owned body when staging is authorized.

See [card and decision validation](references/card-and-decision-validation.md), [targeted lint and staging](references/targeted-lint-and-staging.md), and [cross-card contract review](references/cross-card-contract-review.md).
