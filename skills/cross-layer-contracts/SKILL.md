---
name: cross-layer-contracts
description: Deliver or review contracts spanning application layers, dependencies and runtime boundaries.
license: MIT
---

# Cross-layer contracts

Use when a feature or repair spans several production layers or when a reviewer must establish that the observable behavior survives end to end. Establish the requested scope, whether review or mutation is authorized, and each acceptance criterion before choosing tests.

Map the real input → authority → implementation → serialization → persistence → output path, plus production composition, configuration, asynchronous effects and other surfaces the task actually requires. A passing helper, mocked producer or static declaration proves only that seam. Build a positive/negative evidence matrix; identify preserved behavior and explicitly excluded fallbacks. Follow [boundary verification](references/boundary-verification.md) and, for deactivation or fail-closed changes, [lifecycle and failure contracts](references/lifecycle-and-failure.md).

Test through supported project interfaces with deterministic inputs and the minimum necessary external dependencies. Distinguish a candidate, a delivered local change, activation and live acceptance. Report verified, blocked and untested surfaces separately; do not infer publication, deployment or remote authority from a local check.
