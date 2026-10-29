---
name: kanban-operations
description: Operate Kanban cards, present owner decisions, and verify lifecycle handoffs.
---

# Kanban operations

Use for starting, moving, reviewing, or completing tasks on a project Kanban board. Resolve the board and its supported operations through the project or runtime interface; check current cards and project conventions before changing state.

## Decisions

When a decision is needed, explain its operational consequence and present concrete choices in the same interaction. Recommend one option and its trade-off; use an available choice interface when appropriate. Record the accepted decision on the affected card before the dependent action. If an unanswered decision may be resolved by the runtime's best-judgment policy, choose a reversible option consistent with the actual instructions. See [decision presentation](references/decision-presentation.md) when choosing the interaction.

## Lifecycle

- Present a concise interactive read-back of purpose, acceptance criteria, approach, and affected areas before starting work.
- Follow the project's defined transitions. For the common workflow, preserve `todo → progress → test → ready → done`; pause or cancel only through the supported project mechanism.
- A task reaches `done` only after explicit user approval for that task. Review approval, a profile name, credentials, or a successful gate do not supply that approval.
- If the owner explicitly classifies a card as superseded, history-only, or merged into another card, record the decision and receiving card, including unique acceptance criteria, in both records before archiving it through the supported mechanism. Archival is not implementation completion.
- Add concise execution-log entries after material work, verification, operational actions, or blockers, using the language required by the project.

## Deletion of operational data

Before a separately authorized destructive operation, establish the exact resource boundary, capture durable evidence, and independently verify its count and scope. Perform the narrow authorized deletion, recheck the target and adjacent protected resources, and record the outcome. Creating or moving a task does not authorize deleting its data.

## Verification and handoff

Distinguish static validation, runtime validation, and full-suite results. Report unrelated failures with their owner, and never describe unrun checks as passed. At handoff, summarize verified evidence, remaining work, side findings, and deduplication results. Collect unrelated nits, errors, suspicions, and follow-up candidates; map each to an existing waiting card when possible and state its proposed placement and scope. An active task does not by itself authorize an unrelated card change: obtain explicit owner approval unless the user already requested it or provided a grant covering that change; record that authorization in the card's execution log.
