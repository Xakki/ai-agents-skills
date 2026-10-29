---
name: kanban-acceptance-handoff
description: Verify evidence and hand off a Kanban child without overstating completion.
---

# Kanban acceptance handoff

Use to verify and hand off an implemented child task within the authorized lifecycle scope.

1. Capture branch, tracked and staged diffs, and untracked paths; read the complete current card, criteria, history, parent boundary, and board rules. Preserve unrelated board and repository state. Confirm the selected destination and actual helper effects before moving anything.
2. Separate completed implementation from outstanding acceptance: a project may permit a handoff to `test` while live criteria remain open, but promote to `ready` only when its actual criteria and gates are met. A handoff does not authorize production traffic, deployment, merge, push, or parent completion.
3. Discover and run the actual project-sanctioned checks relevant to the change, including required tests, build and infrastructure or supply-chain gates. A newly added script is not proof that a required wrapper exists; add a missing target only if in scope. Before carrying prior evidence forward, verify its source revision and relevant scope still match; label carried results as historical rather than newly executed. Changed pins or new destination criteria require affected checks again. Identify failures, skips, missing dependencies, and limits accurately.
4. Perform a fresh read-only independent review after the final repair when the task requires and authorizes it. Correct in-scope findings, repeat affected checks and review, and report unresolved or unrelated findings without broadening the task; follow any specified review-round limit.
5. Record sanitized evidence and concrete outstanding pass conditions, then perform only the authorized transition. Run the board's targeted lint and verify it actually checked the intended card; distinguish whole-board baseline failures from the new card. Verify the destination, any status fields maintained by the format, and staged versus working changes separately.
6. Report what was verified, what remains, and the next owner or action. Do not include secrets, raw credentials, request bodies, or unrelated private data in the card.

Use [adjacent transition and lint](references/adjacent-transition-and-lint.md) for source/destination and index verification. State actual remaining metrics and pass conditions without inventing thresholds. Do not generalize a narrow successful check into a host-wide pass or call a failed test an environment limitation without investigating the failure.
