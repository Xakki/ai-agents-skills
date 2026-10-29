---
name: dirty-worktree-selective-commits
description: Prepare and verify scoped commits in a dirty Git worktree.
license: MIT
---

# Dirty worktree selective commits

An inventory is read-only and does not authorize a commit. For an authorized commit, freeze the allowed paths and hunks, preserve existing foreign staging, include new files and both rename endpoints, and inspect the entire staged candidate and resulting commit. A checkpoint is not acceptance.

Read [preservation and index guidance](../git-flow/references/preservation-and-index.md). For partial-file staging or interrupted work, use [selective index and recovery](../git-flow/references/selective-index-and-recovery.md); for linked-worktree inclusion, use [content coverage](../git-flow/references/worktree-content-coverage.md). Follow the user, project and runtime authorization for each operation; this skill does not grant additional authority.
