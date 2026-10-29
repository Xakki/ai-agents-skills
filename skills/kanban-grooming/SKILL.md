---
name: kanban-grooming
description: Groom Kanban work into scoped, decision-complete, verifiable cards.
---

# Kanban grooming

Use for turning a request or existing draft card into implementable work. Read the authoritative project contract, current card and board, existing decisions, dependencies, and applicable instructions before changing anything. Grooming alone does not authorize implementation or publication.

1. Reconcile requested work against a stage-aware inventory of active, completed and relevant ignored or untracked cards; follow legacy IDs to canonical successors. Separate genuine implementation from historical or organizational records and assign each candidate a disposition. Do not delete a discovery note or retire a duplicate until its unique scope and evidence have an authorized destination. Keep ownership boundaries, dependencies, exclusions, and controlled operations explicit.
2. Resolve facts through bounded discovery. Present material owner choices with their consequences and available alternatives; honor the user's requested question cadence and approval gates. Do not treat a timeout or empty answer as approval. Record the actual selection in the canonical decision record and reconcile affected active claims without erasing history. A partially answered choice remains open for its unresolved portion. Once a decision is recorded, continue the authorized queue unless the owner imposed a per-card stop.
3. Specify concrete scope, acceptance criteria, required inputs, verification method, dependencies, and stop conditions. Separate an unknown result that the task is meant to discover from a missing design decision needed to execute it. Trace source authority and consumer boundaries before asserting an existing behavior; distinguish static evidence from a live observation. Avoid inventing numeric requirements, project paths, runtimes, or agents.
4. Before promotion, reconcile unresolved questions, contradictory decisions, duplicate IDs, linked children, and any inherited safety or privacy requirements. A card is not implementation-ready while a required owner choice remains open.
5. Validate the exact changed records with available board checks and diff hygiene; require a nonzero checked-card count and report excluded stages, unrelated baseline failures and unrun checks separately. Independent review occurs at the authorized phase. Use only the requested lifecycle move and do not broaden Git or release scope.

For a decision that changes operational behavior or safety, use [decision recording](references/decision-recording.md), [queue and evidence](references/queue-and-evidence.md), and [security and operational boundaries](references/security-and-operational-boundaries.md) to check authority, the proposed mechanism, and acceptance boundaries before presenting options.

For an epic, interdependent cards, or an independent plan review, consult [dependency and scope planning](references/dependency-and-scope-planning.md). For measured performance, request-accounting, or experimental visual gates, consult [measurement contracts](references/measurement-contracts.md).
