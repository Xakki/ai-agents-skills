---
name: isolated-test-runtime
description: Design and verify isolated integration or end-to-end test lifecycles without touching shared or production state.
---

# Isolated test runtime

Use when the task requires integration or end-to-end tests to be isolated from shared or production resources. Identify the real test runner, supported infrastructure, scope, data stores, credentials, network and exact authorized lifecycle before executing. Isolation requirements follow the actual project; a particular container system is not universally required.

Use uniquely owned test resources and test-only configuration. Fail closed if necessary configuration is absent or ambiguous; do not inherit production secrets or silently reuse shared databases, caches or project names. Limit network exposure to the intended test interfaces and prove the actual process, mounts and endpoints honor the boundary. Fake tools must be used by every downstream helper; an outer fake alone does not prove isolation.

Bootstrap required schemas and fixtures idempotently, then verify the actual authenticated or functional readiness needed by the test; a generic health check can be narrower. Track the real test process and result. Serialize tests that share mutable state unless isolation is established. Distinguish setup, runner, assertion, cleanup and environment failures.

Cleanup only exact resources created and owned by the authorized test, with bounded operations and preservation of the original test failure if cleanup also fails. Never prune shared resources based on broad names. On a disposable fixture, verify both expected cleanup and preservation of unrelated resources. State missing or unrun isolation checks rather than claiming a safety boundary from configuration alone. For validation reporting, see [validation evidence](../validation-evidence/SKILL.md).
