---
name: concurrent-repository-coordination
description: Coordinate concurrent repository work without corrupting shared state.
---

# Concurrent repository coordination

Separate read-only discovery from writers. Serialize conflicting writes and index/ref changes, or run authorized gates against a complete immutable snapshot when unrelated concurrent edits are allowed. Preserve landed partial work and wait for actual writer completion before review.

Read [workstream coordination](../git-flow/references/workstream-coordination.md). If a shared-worktree race occurs, use [concurrent writer recovery](../git-flow/references/concurrent-writer-recovery.md). Follow the user, project and runtime authorization for each operation; this skill does not grant additional authority.
