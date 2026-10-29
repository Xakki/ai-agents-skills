# Persisted request audit trail

Establish the actual event, tenant or owner scope, authorized reader, source of identity, data fields, retention and delivery requirements before designing an audit trail. An event logged at request start is not proof of the final response; define how completion, streaming, cancellation and error outcomes are represented according to the real contract.

Persist only bounded allowed fields; do not store raw request bodies, credentials or arbitrary untrusted metadata simply because the receiver is internal. Enforce the actual reader's authorization at the durable resource boundary. Distinguish append-only semantics, integrity guarantees and retention policy from what the chosen store actually proves.

When the approved business contract requires an audit entry or outbox intent to accompany a state mutation, commit those durable effects atomically at the real storage boundary. Failure to write a required audit or intent must not be reported as a successful atomic operation. A later external publish can succeed before its acknowledgement or checkpoint; define retry, deduplication and recovery based on the actual consumer and transport rather than promising exactly-once delivery.

A transaction in one store cannot by itself roll back an external call or a mutation in another store. Keep their ordering, idempotency and reconciliation contract explicit; do not describe sequencing alone as cross-store atomicity.

Exercise duplicate completion and concurrent or failed writes when required, and verify allowed and forbidden reads with synthetic data through the real supported boundary. A successful logger call, configured retention or in-memory mock is not proof that the durable record was stored or is accessible to the correct owner. Preserve the original application outcome and report unavailable evidence without inventing a guarantee.
