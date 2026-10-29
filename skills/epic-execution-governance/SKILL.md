---
name: epic-execution-governance
description: Plan and govern a multi-card Kanban epic with explicit dependencies and evidence.
---

# Epic execution governance

Use for planning or delivering an existing multi-card epic. Establish the canonical parent and authorized project before broad discovery; a branch name alone does not prove epic identity.

Inventory every declared child against the actual board, including available untracked records. Distinguish parent and external dependencies from children, identify duplicate or historical cards, calculate stage counts, and distinguish lifecycle from acceptance. Compare old blockers with current source and recorded owner decisions; preserve accepted unchanged evidence without treating an unverified gate as passed.

Plan only the remaining executable scope. Split genuinely independent work at ownership and dependency boundaries, record security or live-data operations as controlled scope, and keep project-specific release rules in the project. Preserve canonical child IDs and historical provenance when regrouping; verify allocator and move behavior, including symlinks and previously allocated counters, before invoking them. Never advance grooming with unresolved questions or gates. A planning request does not authorize implementation, card moves, commits, or production actions.

During authorized execution, preserve the owner's decision sequence, selected roles, source revisions, and mandatory stage-entry gates. Avoid overlapping writers; include relevant untracked work in the complete candidate and obtain independent review where required. Reconcile a later owner decision with affected cards while preserving its narrower scope and historical rationale. A running process remains pending after an observation timeout: retain its handle and do not start a duplicate executor or gate. Distinguish runtime limits from explicit owner-limited operations, and continue authorized unfinished work without inventing a new quota. A native security refusal is a stop for the denied operation, never a reason to bypass it.

Before each stage move, reconcile its criteria, approval, existing status fields and evidence, then validate the actual card and checked count. If broad gates and review are explicitly deferred, keep each child at the last stage whose entry rules are satisfied, run required focused checks, and complete the deferred combined gates and review at the agreed point. Mark omitted checks NOT_RUN; an omission is not a pass or waiver. Do not start a reviewer while assigned source edits or mandatory gates remain incomplete. Qualify each executor's completed phase against its actual deliverable, not merely its exit or final wording.

Keep provider acceptance separate from downstream consumer integration and preserve genuinely independent prework as such. Classify review blockers as defects, missing evidence, scope ambiguity or a later Git/lifecycle predicate; fix or clarify the actual blocker, preserve earlier receipts, and rerun only affected required checks. Route out-of-scope findings to existing work with owner approval before changing another card. Distinguish commit, merge, push, deploy and data-operation authority. Explicit user approval is required for `done`.

Report every declared child, actual stage, ordered remaining work, prerequisite, checked versus unrun evidence, and parent-level acceptance. All children being `ready` does not itself prove parent completion, production readiness, or permission to perform `done` or release actions.

Use [interrupted child recovery](references/interrupted-child-recovery.md) when resuming incomplete execution, and [epic finalization](references/epic-finalization.md) only for an authorized coordinated completion.
