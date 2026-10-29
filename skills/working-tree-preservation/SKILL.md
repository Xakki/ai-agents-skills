---
name: working-tree-preservation
description: Preserve unrelated staged, unstaged and untracked work in a dirty Git checkout.
---

# Working tree preservation

Establish the current actor’s permitted baseline before mutation. Keep the index, working bytes and untracked files distinct; preserve opaque content within its authorized boundary. Never overwrite or discard another actor’s changes merely to obtain a clean tree. If damage occurs, stop and recover only from verified authorized evidence.

Read [preservation and index guidance](../git-flow/references/preservation-and-index.md). For linked-worktree inclusion use [content coverage](../git-flow/references/worktree-content-coverage.md); for interrupted selective staging use [selective index and recovery](../git-flow/references/selective-index-and-recovery.md); for investigating saved changes use [stash provenance](../git-flow/references/stash-evidence.md). When protected dirty content constrains an authorized integration, see [isolated squash integration](../git-flow/references/isolated-squash-integration.md). Follow the user, project and runtime authorization for each operation; this skill does not grant additional authority.
