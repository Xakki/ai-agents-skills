---
name: testing-strategy
description: Choose proportionate behavior verification or test-driven development for a software change.
---

# Testing strategy

Identify the behavior, risk, sanctioned runner and task-specific acceptance gates. Favor tests that can observe a meaningful failure at the appropriate boundary instead of duplicating implementation or asserting incidental details. Small reversible changes do not automatically require new tests; follow the user's instructions and project policy.

Use test-driven development when requested or useful: define a focused behavior, observe the expected pre-fix failure where feasible, implement the smallest change, rerun it and applicable broader gates. A collection failure is not a meaningful regression RED. A test written after implementation can still provide valuable verification; preserve existing user work and do not delete code to force test-first order.

Use isolated fixtures and test doubles where they protect real boundaries, and verify actual integration paths where necessary. Distinguish static inspection, focused test, full gate and runtime behavior. Report exact outcomes and any unrun or blocked checks, without introducing unsanctioned service changes, commits or deployment.
