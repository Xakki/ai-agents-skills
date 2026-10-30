# Fixture isolation and lifecycle

Identify shared mutable state across databases, queues, files, caches, singleton objects, environment, processes and test framework lifecycle. Establish ownership, initial state and teardown order. A focused pass does not prove a suite is order-independent; an ordered state-bleed probe can establish whether a later test observes a predecessor's residue.

Use the actual application boundary required by the claim and isolate only external effects that the test is allowed to replace. Failure-path cleanup should not prevent restoration of other owned state or framework teardown; distinguish a cleanup error from the original test failure. Verify retained or removed resources under the exact owned scope, and preserve unrelated state.

Register cleanup as each owned resource is created, including partial setup failure; verify all owned persistence surfaces and dependency order. Where tests share a parent resource, clean only captured child identities, not all records under the parent. Observe product effects before fixture teardown can hide them.

Control test concurrency or use independently proven fixtures. A simulated list that omits unrelated resources cannot prove a selector or cleanup preserves them. Attribute each result to the tested candidate and path; do not claim timeout, crash or teardown behavior that was never exercised.
