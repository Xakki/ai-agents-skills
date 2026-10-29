---
name: test-harness-integrity
description: Verify test runner selection, fixture isolation and result evidence at the actual execution boundary.
---

# Test harness integrity

Use when a test runner, wrapper, fixture or report gate might misrepresent what actually ran or how it was isolated. Identify the requested test, selected inputs, runner and consumer, allowed effects, expected evidence and real completion status. Inspect actual selector and collection behavior; source test presence, a wrapper's zero exit or a printed summary alone may not establish that the intended test ran.

For artifact-gated runners, distinguish child failure, valid evidence and a zero-exit child with missing or malformed evidence. Bind the actual producer's final artifact to the real consumer, preserve child and wrapper statuses separately, and do not let cleanup replace a primary failure. Test both valid controls and causally rejected negative cases where authorized.

When primary work succeeded but mandatory cleanup failed, report cleanup failure as a failure of the complete lifecycle. When both primary work and cleanup failed, retain both outcomes and the primary failure rather than hiding either.

For mutable state or cleanup claims, inspect [fixture isolation](references/fixture-isolation.md). For complex fake tooling or result pipelines, inspect [harness oracles](references/harness-oracles.md). Run checks through the project's supported interface and report actual selected scope, counts, errors, unrun checks and limitations. A synthetic fake or local fixture proves only the boundary it actually models; it is not independent review or real-runtime acceptance.

For claims about real persisted state, transaction rollback, or ownership fences, consult [persistence evidence](references/persistence-evidence.md).
