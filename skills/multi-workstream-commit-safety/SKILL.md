---
name: multi-workstream-commit-safety
description: Commit multiple authorized workstreams without mixing excluded work.
license: MIT
---

# Multi workstream commit safety

Resolve the owner’s approved scope, branch, commit count and order before staging. Explicitly account for each workstream and shared hunk; validate each requested intermediate candidate and preserve protected or unclassified content. Verify the actual commit and remaining state.

Read [workstream coordination](../git-flow/references/workstream-coordination.md). For an interrupted checkpoint or shared-file index, use [selective index and recovery](../git-flow/references/selective-index-and-recovery.md). Follow the user, project and runtime authorization for each operation; this skill does not grant additional authority.
