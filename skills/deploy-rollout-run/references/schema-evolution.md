# Schema evolution evidence

Establish the exact source history, applied revision and authorized datastore before action. An edited source migration does not update stores that already recorded the previous version. Respect the project's applied-migration contract; prefer an authorized forward repair where changing an already-applied revision would create divergence. Treat unexplained drift as unresolved rather than resetting or stamping a shared store to make a gate pass.

Distinguish a fresh installation, upgrade from real earlier state, persistence and reload, and supported reversal or reapplication. Exercise each required chronology only in an authorized isolated or explicitly approved environment. Inspect effective constraints and historical rows at the real persistence boundary; generated schema or a source-only assertion does not prove migrated state. Leave unavailable paths unverified and do not weaken a forward-only contract to satisfy a generic rollback checklist.

Check relevant ownership, foreign-key and deletion behavior, transaction boundaries, identity fences and retention semantics against the actual contract. Do not invent security credentials for legacy state from predictable identifiers. Preserve unrelated data, snapshots and live services; report candidate and actual results separately from proposed rollout.
