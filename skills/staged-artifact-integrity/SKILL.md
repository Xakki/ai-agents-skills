---
name: staged-artifact-integrity
description: Verify staged artifacts and preserve unrelated Git index entries.
license: MIT
---

# Staged artifact integrity

Record the original staged and working state and exact permitted artifact paths. A successful add or a matching filename list does not prove correct staged bytes. Compare the complete staged blobs, modes, deletions and rename endpoints with the approved candidate; inspect normal hooks and the actual commit.

Read [preservation and index guidance](../git-flow/references/preservation-and-index.md). For shared files, staged renames or interrupted commits, use [selective index and recovery](../git-flow/references/selective-index-and-recovery.md). Follow the user, project and runtime authorization for each operation; this skill does not grant additional authority.
