# Durable acceptance and duplicate diagnostics

In independent review, freeze the candidate and inspect the real path from input through fence, transaction, journal, post-commit effects, retry and public result. Keep implementation correctness separate from live provider or deployment evidence. Use current observed outcomes and a positive control, plus deliberate failures before, during and after each decisive transition. Test ordinary replay, conflicting replay, stale owners, expiry, crash after external effect but before checkpoint and concurrent claim; use the real transactional engine in an isolated fixture where the contract depends on its locking behavior.

When one trigger appears as duplicate events, trace a bounded, authorized execution through source emission, transport, collectors, parsers and sink. Compare safe counts and correlation metadata at each boundary to find the first multiplication; do not silently deduplicate at the sink before understanding the source. A synthetic local test does not establish production delivery. Record unavailable observations and avoid raw payloads or secrets.

Report the expected and observed state and effect counts, deciding failure or success, current candidate identity, exact scope and unresolved evidence. Partial focused results do not prove complete durable recovery or every external side effect.
