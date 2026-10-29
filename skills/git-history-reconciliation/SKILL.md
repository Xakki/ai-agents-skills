---
name: git-history-reconciliation
description: Reconcile divergent Git histories while preserving recoverable source state.
---

# Git history reconciliation

Identify exact source, target, topology and requested result. Preserve adequate authorized recovery artifacts before history or ref mutations, account for additions and deletions, and compare the final candidate with the retained source. A local rewrite does not authorize remote publication or force updates.

Read [branch history and retirement](../git-flow/references/branch-history-and-retirement.md). For linked-worktree inclusion after squash integration, use [content coverage](../git-flow/references/worktree-content-coverage.md); for protected dirty content during an authorized squash, use [isolated squash integration](../git-flow/references/isolated-squash-integration.md). Follow the user, project and runtime authorization for each operation; this skill does not grant additional authority.
