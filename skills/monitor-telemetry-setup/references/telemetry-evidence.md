# Telemetry delivery and measurement evidence

Identify the exact producer and scope, export temporality, units, relevant timestamp and instance identity. Check that intermediate stages accept and correctly transform the actual format; successful ingress alone does not prove downstream persistence. Query the stored series or event using a narrowly scoped synthetic identifier, time window and correct field names; an empty search also requires a working positive control.

For aggregates, establish whether values are totals, rates, observations, estimates or samples, and whether resets, short-lived producers, duplicate delivery or multiple instances affect the calculation. Ensure each real operation is counted according to the contract, including errors, retries, fallback, cancellation and streaming when relevant. Do not assert exact savings, independent samples or full-lifetime totals from data that cannot support them.

For derived percentages or rates, use inputs from compatible scopes and observation windows and require a valid denominator. Keep unavailable, stale, reset or invalid inputs unknown rather than coercing them to zero. A configured policy or nominal resource limit is not proof of its effective runtime behavior.

When a structured field disappears, compare a safe known-present sibling through the same producer, parser, transformations, serialization and stored-field mapping. Verify downstream query-required fields remain present after sanitization; populating a display field does not authorize dropping a separate consumer field. Enforce the final formatted privacy boundary without reintroducing sensitive query parameters or raw request data.

Estimate and observe series cardinality, retention and resource costs before a high-volume rollout. If reducing histogram resolution, state the percentile-precision tradeoff and verify affected counts and sums along with unaffected controls. A local fixture demonstrates only its own dataset and runtime; it is not a capacity or live-producer guarantee.
