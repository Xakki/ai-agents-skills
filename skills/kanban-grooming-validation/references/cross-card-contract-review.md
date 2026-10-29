# Cross-card contract review

When related cards define a shared contract, reconcile identity and routing, owned actions, state-machine boundaries, idempotency, retry and expiry behavior, and which component owns policy, transport, UI or audit effects. Keep timeout, unknown, terminal success/failure and retention expiry distinct. State the fingerprint and conflict semantics when idempotency applies. Reflect approved terms consistently in the affected cards' recommendations, acceptance and decisions; keep unapproved storage, retention, rollout, permissions and ownership questions open.

For explicit input selectors, define the closed supported values and their actual mapped inputs, reject missing or inapplicable values, and test normal, edge and mismatch cases. If replay/audit is required, persist the effective input and options and test that replay consumes them instead of guessing from a mode or payload. Keep unmeasured thresholds and production defaults unresolved until the owner decides.

For durable-state tests, define test ownership and exact cleanup keys; verify cleanup only for resources the test owns. A service-level no-data assertion, an HTTP mapping test and end-to-end/release validation prove different boundaries and must be recorded separately.
