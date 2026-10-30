# Producer and consumer response validation

Trace the producer's DTO and serializer through the final wire representation to the actual consumer. Record required and nullable fields, types, ranges, string patterns, date grammar, collection limits and uniqueness. Use separate schemas for different endpoints and outcomes, such as an issued one-time secret versus metadata-only lists. Permit or reject unknown fields as the real contract specifies.

Check semantic validity as well as shape. For date/time values, verify actual producer normalization, grammar, offset, precision and calendar validity; generic parser success may normalize impossible dates. For generated configuration, assert the decoded type in the consumer as well as serialized text: a format name alone does not guarantee how ambiguous scalars decode. Strictly validate fields that govern security or business decisions without rejecting valid representations of unrelated external structured fields.

Malformed success and transport failure need explicit safe state behavior. Where the contract requires it, clear transient secrets and stale displayed metadata and return a bounded sanitized error. Test using valid baseline builders and one adversarial change per case: bad type, length, token-prefix mismatch, date, duplicate identifier, item limit, nullability and unexpected nesting. Seed prior state when proving it is cleared.

For pagination, trace the producer's meaning of totals, pages, cursor and bounds. Distinguish raw upstream coverage from new or deduplicated valid items; a short page that contradicts reliable total metadata must not silently certify completion. Missing optional echoes do not disable other available checks. Use consistent multi-page positive fixtures and contradictory negative controls.

In review, distinguish an actual decoder/consumer defect from a missing test or unavailable execution. Include the exact accepted input shape, failing boundary and observable impact; do not run live services or mutate state unless separately authorized.
