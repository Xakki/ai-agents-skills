# Health-backed API review

For a read-only review, map route/auth handling, query defaults and every result category. A filter must cover each category promised by the contract, including fallback or alias projections. Trace producer → durable state → reader → response: compare identity, location, timestamp, freshness, failure and corrupt-state handling.

Keep missing state distinct from present but entirely stale or failed state; an intentionally fail-open empty cache does not imply fail-open for a known failed population. Inspect the actual refresh mechanism, write atomicity, concurrency and reader configuration. Compare runtime responses, typed model and any generated API schema, including extension fields.

Check that fallback probes retain intended options and do not produce artificial health results. Report findings with the complete source-to-observed consequence and distinguish static evidence, tests actually run and unverified deployment hypotheses. A static review does not authorize live provider calls.

When eligibility uses health observations, trace operator policy, declared
capability, requested operation, canonical identity and runtime evidence as
separate inputs. Check each routing and catalog entry point, including explicit
selectors, aliases, inferred choices and fallback. Preserve request provenance
when its policy differs. Do not infer one capability's health from another or
turn one model's observation into a global provider veto without a documented
contract. A stale imported mapping or destructive filtering of a shared candidate
list can hide recovery after state changes; test current metadata and a later
healthy resolution without corrupting the original candidate set.

Separate last attempt, last success, their timestamps and any newer failure;
a historically successful result does not by itself establish current health.
Specify absent, empty, stale, invalid and future-dated state under the project's
actual policy. Test both the execution selector and its visible catalog
projection with controlled fixture state, including unknown and custom entries.

When extending a persisted health schema, trace old and new readers and writers
in both update orders. A new capability-specific record must not silently
clobber unrelated existing observations or turn an absent legacy field into a
measured failure. Define authority and compatibility from the actual migration
contract; test mixed-version operation and the projected public result.
