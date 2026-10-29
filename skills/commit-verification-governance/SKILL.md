---
name: commit-verification-governance
description: Verify a repair commit while preserving uncommitted test work.
---

# Commit verification governance

Use when reviewing a repair commit alongside uncommitted tests or fixtures. Preserve unrelated staged, unstaged, and untracked changes; do not discard or rewrite a test merely to make the worktree look clean.

1. Capture the target commit, branch, relevant status and diffs, and actual test scope before editing. Inspect the uncommitted tests and identify which behavior each constrains; retain legitimate coverage and report unrelated or uncertain work to its owner.
2. Translate the repair into observable outcomes and exercise the affected public behavior with the project-sanctioned checks. Include failure-before-write behavior, relevant interfaces, and fixture compatibility when applicable. Discover the supported runtime rather than imposing a container, network mode, or test command.
3. Distinguish current passing, failing, blocked, skipped, and unrun gates. A focused pass does not make a blocked full suite green; a stale fake or cache miss must be described with its actual cause and evidence, not silently rewritten or mislabeled.
4. Make a focused test-only follow-up only when the task authorizes it. Follow the repository's message and trailer policy, preserve normal hooks, avoid unrelated formatting churn, and verify the actual resulting commit, paths, excluded changes, and artifact identity.
5. State the verdict and direct blocker from observed evidence. Never claim runtime compatibility, clean state, or acceptance beyond what the checks established.
