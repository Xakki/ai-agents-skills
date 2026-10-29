---
name: git-flow
description: Safely inspect and perform scoped Git work, including commits, branches, merges, pushes and pull requests; коммит, ветка, пуш, слияние, пулреквест.
---

# Git workflow

Use for Git operations when the task needs a clear scope, preservation of existing work, or verification of a commit or ref. Follow the user, repository and runtime policy for the current task; loading this skill does not grant permission to commit, rewrite history, push, merge, deploy or contact others.

1. Resolve the exact repository, worktree, current branch, destination and requested operation. Preserve the current branch unless the task or project policy requires another; do not infer a branch, remote or publication target from an example.
2. Before mutation, inspect the authorized worktree and staged state at an appropriate scope. Distinguish existing changes, other agents' work and private files; do not read or stage content outside the permitted boundary. Coordinate overlapping writers and preserve pre-existing index entries.
3. Stage only the authorized paths and changes. Check the complete staged diff and path list before committing: selecting paths to add does not remove other entries already staged. Handle mixed hunks and partially staged files without silently adding unrelated work.
4. Preserve the requested commit subject, body and trailers exactly; do not add attribution or other trailers unless requested or required by applicable project policy. Keep normal hooks and signing requirements enabled. Use [message and staging guidance](reference.md) when the message or index needs careful handling.
5. For an authorized commit, verify its ID, message, parents and affected paths against the intended result; separately report remaining work and failed or skipped checks. Do not amend or rewrite history without the necessary authorization.
6. For merge, rebase, push, PR or deployment, verify the actual source and target and the authorization for each effect. Recheck the relevant refs before an authorized publication and confirm its result. A successful commit or local check is not evidence of remote publication or deployment.

Resolve specialized skills through the runtime when needed: use a scoped move/remove workflow for file relocation, the project's Kanban policy for card lifecycle, and the project's own review or test gates for acceptance. A skill name or a stated role does not grant additional authority.
