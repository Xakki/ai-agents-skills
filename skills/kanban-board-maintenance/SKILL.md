---
name: kanban-board-maintenance
description: Repair or reorganize Kanban boards while preserving task scope and stages.
---

# Kanban board maintenance

Use for reorganizing an existing board, creating missing organizational parents, or repairing card relationships. Do not implement work merely because a card describes it.

1. Resolve the authoritative board and its supported operations through the project or runtime. Inventory relevant stages, existing parents, links, dependencies, and pending work; preserve unrelated uncommitted edits when the board is repository-backed.
2. Keep children in their actual stages and completed work as historical references. An organizational parent does not itself advance, reopen, or complete a child. Do not edit a child merely to restate a relationship, or create multiple parents for the same child.
3. When authorized to create parent epics, use the board's actual template and include purpose, ordered child IDs and paths, current stages, blockers, non-goals, and integration criteria. An existing parent is not a reason to omit other requested parent cards. Mark overlapping implementation as a decision to resolve rather than silently duplicating it.
4. Archive a superseded executable card only when the owner explicitly authorizes that disposition. Record its replacement and unique acceptance evidence in both records, update affected parent references, and use the supported archive operation. Preserve historical context; label resolved or deferred questions so they are not mistaken for active gates. Archival is not completion.
5. Validate the exact changed cards and the board using its available linter. Distinguish newly introduced failures, unrelated pre-existing failures, excluded stages, and unrun checks. Verify the requested number and names of cards and required sections. If an explicitly requested naming convention causes a warning, report the warning rather than silently changing the allocation state. For repository-backed boards, verify whitespace for both tracked and new files, and confirm only authorized cards and paths changed. Do not stage unless authorized or commit without an explicit user request.

Report the created or modified records, verified checks, existing blockers, and unresolved decisions. Never alter a completed card or product code unless the task explicitly includes that action.
