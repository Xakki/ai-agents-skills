# Delivery outcome and retry boundaries

Use for durable delivery queues and other external effects where a failure can
occur before dispatch, during transport, after remote acceptance, or while
recording a local result. Trace producer, durable enqueue, claim/lock,
transport and committed outcome separately; stopping a producer does not prove
that an independently running sender stopped replaying existing work.

Classify retry eligibility from the actual transport contract and evidence,
not broad text or a generic status alone. Authentication, permanent rejection,
unknown outcomes and potentially post-acceptance failures need distinct policy;
an uncertain response or a local transaction failure after dispatch is not
proof of non-delivery. Preserve the operation and recipient identity for
reconciliation, respect the target's proven idempotency mechanism if one exists,
and never claim exactly-once from local locking alone. Apply an explicitly
configured bounded attempt budget; do not silently select historic failures or
use a retry as a diagnostic probe.

Exercise exact claim and settlement boundaries in the actual worker transaction:
pre-dispatch failure, accepted delivery, explicit retryable rejection, terminal
failure, ambiguous acceptance, persistence failure, concurrent claim and an
empty queue. Verify the persisted status, attempt count and forbidden effects
through synthetic transports, including both a valid control and protected
historical records. Report local acceptance separately from independent remote
receipt. Live sends and bulk retries require authority for their exact scope.
