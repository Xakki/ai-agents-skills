---
name: simplify-code
description: Simplify a specified change by removing duplication and needless complexity without changing its contract.
license: MIT
---

# Simplify code

Use when the user requests simplification or cleanup of a specified change. Respect a report-only request and the exact requested diff, files or revision; preserve unrelated work. If the scope is unclear, inspect the available changed paths and establish what is actually in scope.

Review the change and surrounding implementation for reuse, avoidable complexity, unnecessary work and fixes applied at the wrong abstraction boundary. Verify what the existing code does and why a proposed simplification is safe; compare useful existing helpers instead of adding new abstraction for its own sake. Keep externally visible behavior, privacy, compatibility, resource bounds and concurrency guarantees intact.

Delegate only when authorized and supported by the current runtime; do not assume a specific number, profile, agent API or model. Otherwise perform the relevant review angles directly. Deduplicate findings and prefer concrete, consequential improvements over style churn. Apply changes only within the user's authorized scope; flag a change that alters the contract or needs an independent product decision. Run focused checks appropriate to the changes and report what was changed, what was only proposed and any unverified behavior.
