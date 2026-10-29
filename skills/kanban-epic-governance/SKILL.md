---
name: kanban-epic-governance
description: Record Kanban epic scope, dependencies, pauses, and acceptance boundaries.
---

# Kanban epic governance

Use when an epic needs a durable scope decision, a dependency pause, or an authorized reduction in scope. Read the complete parent and affected children first; preserve existing history and unrelated work.

Record a concise current decision digest with the epic and ordered child IDs, pinned predecessors when relevant, acceptance gates, authorized actions and limits, current baseline, parked risks, and an explicit paused state when a dependency blocks execution. Verify actual repository or service state instead of treating card prose as proof. Mark superseded statements at their original location so the active plan is not contradictory.

When the owner approves reducing scope, distinguish remaining children from deferred standalone work; keep their criteria and dependencies. Reconcile the parent sequence and references, and use the supported board operations only for authorized card changes. A smaller scope does not accept an unfinished child or authorize parent closure.

Before moving excluded cards, verify standalone IDs are unique across the board, retain old epic IDs as historical provenance, and preserve their criteria and decisions. Update the parent's active child list, execution order, dependencies and completion criteria together. Do not start or move children while a blocking predecessor is unresolved.

Validate every changed record with the canonical board checker where available, inspect exact changes and any scoped review, and report unavailable checks. If a commit is authorized, stage only the explicit intended records, including both sides of a rename, and verify committed paths and post-commit status. Follow the task's Git and authorization policy rather than inventing a branch, trailer, commit, or publication requirement. Report the current scope, deferred children, gate results and precise remaining parent blocker.

See [pause digest](references/epic-pause-digest-session.md), [preparation staging](references/epic-preparation-staging.md), and [parent start verification](references/parent-start-verification.md) for supported steps.
