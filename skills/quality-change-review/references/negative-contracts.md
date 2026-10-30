# Negative contract review

Translate each accepted negative guarantee into an observable boundary: no network, write, cross-tenant access, fallback, leaked credential or duplicate side effect are different claims. Trace the public caller and every reachable producer or resolver; a helper passing alone may not cover the integrated path.

Use existing sanctioned tests and isolated fixtures where authorized. For a no-write claim, a refusal alone does not prove state stayed unchanged: inspect the authorized state boundary or use a writable-operation guard. For no-network, verify actual transport isolation or an observable denied-call boundary. For cancellation and exact-once claims, exercise the relevant early close or failure and count effects when feasible. Static inspection, a fake and a runtime test answer different questions; label the evidence used.

Check that the test selects the relevant path, the fixture can express the forbidden behavior, and assertions inspect the actual result; do not infer complete coverage from a happy path. Mutation or side-effecting probes require their own authorization and safety. Report missing evidence without inventing a defect or claiming a guarantee.
