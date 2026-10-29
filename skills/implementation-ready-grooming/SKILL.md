---
name: implementation-ready-grooming
description: Groom cross-boundary work into measurable, dependency-safe Kanban tasks.
---

# Implementation-ready grooming

Use to turn a cross-component request into cards that an implementer can execute without inventing unresolved product decisions. Respect the owner's planning and delegation mode; grooming does not itself authorize implementation.

1. Inspect the authoritative contract, generation path, affected producers and consumers, existing work, and current cards. Distinguish the requested delta from already-completed work; resolve source facts through bounded discovery before asking the owner. When code and product documentation give a field incompatible meanings, obtain the owner's decision on migration versus a separate field before deciding product semantics.
2. Split work by responsibility and real dependencies, not matching keywords. Specify the authority and meaning of each reused field, including producer, consumer, units, unavailable state, compatibility, and security boundaries where relevant.
3. Turn qualitative criteria into measurable observations with the applicable input, method, window, aggregation, cardinality, unavailable state, and pass conditions. For resource-efficiency claims specify the device/profile, observation window, budget and measurement source. Identify existing project verification commands, including shared cross-package harnesses, instead of inventing a runner or dependency.
4. Record dependency edges and completion gates on both parent and child records where the board supports them. Preserve exclusions, blocked predecessors, and integration criteria.
5. Present consequential choices and trade-offs, then record each accepted decision. An unanswered material choice remains unresolved unless the owner has explicitly delegated it; do not infer consent from a timeout.
6. Validate the actual changed cards and their source pins, including new or ignored files. Require a nonzero targeted checked-card count and run the relevant diff check. Distinguish targeted checks and unrelated whole-board failures. Review independently only when the task authorizes it; otherwise report the self-check. Stage or commit only within the authorized scope. When later independent review is explicitly deferred until implementation and its gates finish, preserve that order; do not mark unresolved choices as complete.

For each field, distinguish a reported claim from authoritative evidence; do not infer an unrelated target's network identity from the control connection. Specify sender, receiver, timing and feedback direction. Give round-trip measurements their correct meaning, and specify aggregation shape and percentile method rather than calling unbounded statistics bounded.
