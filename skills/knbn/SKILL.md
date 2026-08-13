---
name: knbn
description: Alias for the kanban skill. Use when the user invokes or refers to Kanban as "knbn".
---

# knbn — Kanban alias

`knbn` is the portable invocation alias for the shared [kanban](../kanban/SKILL.md)
workflow. It deliberately has its own real skill directory rather than being a
symbolic link: all supported plugin runtimes discover `skills/*/SKILL.md`, while
symlink traversal is not a cross-runtime compatibility guarantee.

Load and follow the canonical [kanban skill](../kanban/SKILL.md) for the complete
board lifecycle, scripts, and safety rules. `knbn` adds no behavior and must stay
semantically identical to `kanban`.
