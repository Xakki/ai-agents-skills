---
name: kanban-lifecycle-operations
description: Perform evidence-backed Kanban lifecycle moves and verify their effects.
---

# Kanban lifecycle operations

Use when an authorized task requires moving cards or preparing a verified handoff. Resolve the current board, exact source and destination, task-specific authority, and applicable gate before touching state. Preserve unrelated staged, unstaged, and untracked work.

Read the complete card, decisions, source pins, current acceptance evidence, and board rules. A stage transition does not itself grant another action. Require explicit user approval for `done`; assess merge, push, deployment, worktree creation, and scope expansion separately. Honor a newer explicit owner decision without discarding independent required gates.

Determine the eligible stage from actual project criteria: local implementation may enter a QA stage with live acceptance still pending if that stage permits it, while `ready` requires its specified gates. Keep cancelled work and repairs to accepted cards historically accurate; do not invent test results or replay transitions merely for an audit trail. Bind independent review to its actual reviewer and candidate, distinguish accepted code from a failing global gate, and finish active writers before freezing the next phase.

Before a move, inspect the actual helper's board resolution, alias handling, stage validation, and index effects. Run targeted board checks when available and verify that the intended card was checked; zero checked cards is not validation. Perform only an authorized transition, then confirm one canonical destination, absence of the old source, actual maintained status fields, working content, and Git index effects. Record unavailable checks and unrelated failures honestly; report a native security veto without bypassing it.

When a scoped local commit is authorized, preserve normal hooks, use the task's message and staging contract, and verify actual committed paths, message, content, and excluded state. Report a moved card with blocked Git finalization as blocked rather than completed. Read back an authorized remote or deployed result before claiming it succeeded.

For focused procedures see [stage and acceptance](references/stage-and-acceptance.md), [helper and validator effects](references/helper-and-validator-effects.md), and [staged evidence](references/staged-evidence.md).

For cancellation, duplicate reconciliation, or epic parent handoffs, consult [exceptional lifecycle outcomes](references/exceptional-lifecycle-outcomes.md). For a staged rename or compatibility alias, consult [rename and index diagnosis](references/rename-and-index-diagnosis.md).
