---
name: autonomous-kanban-delivery
description: Deliver an authorized Kanban queue while preserving scope and evidence.
---

# Autonomous Kanban delivery

Use when the owner requests autonomous work through a board queue. Read the actual board, scope, lifecycle, dependencies, and applicable project rules before selecting work. A request for autonomous delivery does not imply authority for `done`, merge, publication, deployment, or destructive effects.

1. Inventory the authorized queue across stages and reconcile duplicate IDs, prior child renames, related branches and actual delivered scope. Distinguish executable tasks from historical, blocked, or organizational records. Preserve unrelated worktree and index state. Select unblocked work in an order consistent with dependencies and the owner's priorities; do not reimplement work already evidenced as complete.
2. Resolve each action's authority and exact target. Continue already authorized phases without asking again; preserve stricter phase gates and explicit user approval for `done`. Treat an unanswered material decision as unresolved unless it was explicitly delegated. Record later owner answers and supersede stale pending statements without assuming broader permission.
3. Delegate only when allowed and the runtime can provide the required role. Give each worker its scope, ownership, relevant boundaries, required gates, and current baseline. Avoid parallel writers on overlapping files or shared state. Preserve continuity and partial work after a worker stops; retain a still-running process handle instead of duplicating work. A native security veto stops the denied operation; do not bypass it by changing tools or policies.
4. Make the smallest meaningful implementation and run the required checks. Bind review and gates to the actual tested candidate; report failed, skipped, deferred, historical, and unrun checks separately. Reuse unchanged accepted evidence only when its source and scope still match. A deferred batch-review schedule does not waive any stage-entry gate: retain the last eligible stage and run the required combined checks and review on the completed candidate.
5. Resolve canonical board paths and helper effects before each authorized lifecycle move. Verify the target state, applicable lint, Git index and working changes independently. Use exact owned paths and normal hooks; a routine local commit requires the task's applicable authorization, and unrelated changes remain untouched.
6. Report each task's actual endpoint, evidence, blockers, remaining decisions, active work, and next owner. A completed child, `ready` card, or scoped test is not whole-epic or production acceptance. Do not silently drop unrelated findings; map them to existing work or propose a separately authorized follow-up.

For bounded queue work use [pool checklist](references/autonomous-pool-checklist.md), [decision handoffs](references/decision-handoffs.md), [delivery safeguards](references/delivery-safeguards.md), and [finalization and blocked handoffs](references/finalization-and-blocked-handoffs.md).
