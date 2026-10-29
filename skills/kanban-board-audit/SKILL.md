---
name: kanban-board-audit
description: Audit Kanban cards for duplicate, completed, blocked, and epic-ready work.
license: MIT
---

# Kanban board audit

Use before prioritizing cards or grouping them into epics. Inspect the authoritative board through the project or runtime interface and retain its scope, lifecycle, and authorization boundaries.

1. Capture the initial board state, allocation mechanism, relevant stages, existing epics, and repository status when applicable.
2. Read each source card's title, criticality, tags, scope, acceptance criteria, decisions, dependencies, and status. Search the relevant active and historical stages by ID, title, and subject before declaring a card unique or incomplete.
3. Classify each card as unfinished implementation, historical/discovery record, blocked or controlled operation, or duplicate. Cite the completed work or decision supporting each exclusion. A card's stage alone does not establish whether its work remains.
4. Group implementation cards by actual execution boundary and dependency order, honoring any priority explicitly set by the user. Keep historical ledgers as context and isolate controlled live-data or destructive actions with their required authorization and evidence; do not silently add those actions to an epic. Similarly named credentials or identities are not interchangeable without evidence of the same authority. Do not promote a grooming card while its open questions remain unresolved.
5. When creation is requested and authorized, use the project's allocator and record concrete child IDs, ordering, integration criteria, and decisions. Resolve draft mistakes only within the owner's authorized scope and reconcile any counter against the authoritative board; do not assume rollback is safe.
6. Check the exact changed cards with the project linter when available. Separate targeted results from whole-board results, report unavailable or failing checks honestly, and check the intended Git diff when applicable.

Report the proposed or created epics, excluded records and their supporting evidence, controlled operations, and outstanding decisions. Do not commit without an explicit user request.
