---
name: kanban-delivery-integrity
description: Keep Kanban helper effects, task evidence, and scoped Git delivery separate.
license: MIT
---

# Kanban delivery integrity

Use when board helpers, task changes, evidence, and unrelated work could be mixed during delivery.

1. Record the applicable board, repository status, and staged and unstaged paths before using a helper. Use the canonical allocator rather than inventing identifiers. Discover the helper's supported interface and inspect its actual board, allocation, and Git effects after execution; a printed card path is not a complete effects report.
2. Preserve unrelated index and worktree changes. Distinguish task implementation, its execution evidence, allocation state, and independent debt records. Do not use broad staging, discard foreign staged state, or stage a compatibility symlink.
3. Discover what each existing test target actually runs and run the relevant task and board gates; report exact failures, skipped checks, and unrelated pre-existing failures. Do not present a partially passing or unrun gate as green. Complete implementation and required gates before independent review when required and authorized.
4. Make a local commit only when the task and applicable policy authorize one. Stage the exact owned paths, follow the actual message and trailer policy, verify the resulting commit and intended paths, and preserve unrelated work. Never invent an agent trailer or bypass normal hooks.
5. Record the actual verified endpoint and remaining work on the card. Ready-for-review and out-of-scope rollout are not completed production acceptance. Map independent findings to existing cards before proposing additions; respect the owner's requested authorization for new cards.

For additional details consult [helper effects and commit scope](references/helper-staging-and-scope.md), [review and scope correction](references/review-and-scope-correction.md), and [follow-up triage](references/deferred-follow-up-card-triage.md). A `done` transition requires explicit user approval.
