# State validation and projections

Exercise required/optional keys, nullability, types, unknown versions or enum values, bounds and cross-record relationships. Where runtime type coercion is dangerous, test booleans, non-finite values, numeric strings, subclasses, custom comparison behavior and overflow according to the language and schema; do not turn one language's implementation details into a universal wire rule. Forged or externally restored objects need the same transition checks as normally constructed values.

Capture prior durable bytes and side-effect counts when the contract requires rejected state to remain unchanged. Validate before claim, producer mutation or dispatch, not only at final output. Distinguish a valid historical record from an invalid current generation according to the actual version model.

Trace each state projection into API, CLI, UI, logs and health results. Test missing, fresh, stale, future, malformed and legacy values where applicable; parsing success does not prove date conversion, rendering or health semantics are safe. For mutable markers, leases or endpoint identity used across an exchange, validate the complete relevant snapshot before and after; an unchanged inode alone does not prove unchanged contents.

Use a valid positive control and adversarial negative cases at the real public boundary. Assert refusal and absence of unauthorized external calls, persistence, deletion or state mutation; distinguish fixture setup errors from a deciding regression. Report the exact source, test scope and observed outcome without leaking protected payloads.
