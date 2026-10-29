---
name: merge-parent-reconciliation
description: Review whether a merge preserves compatible behavior from both parents.
---

# Merge parent reconciliation

Perform a read-only review of the pinned merge and both parents. Compare affected files and contracts against each parent, verify relevant tests and actual conflict context, and report precise findings. A marker-free merge is not proof that both parents’ behavior survived.

Read [merge and parent review](../git-flow/references/merge-and-parent-review.md). For parent-by-parent and generated-artifact checks, use [merge parent evidence](../git-flow/references/merge-parent-evidence.md). Follow the user, project and runtime authorization for each operation; this skill does not grant additional authority.
