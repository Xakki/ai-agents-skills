# Data-access performance evidence

Inspect the actual access path, predicates, joins, ordering, existing indexes and expected data volume before attributing slowness or proposing an index. Measure the current plan and workload only through an authorized supported interface; do not expose credentials or use production load without explicit scope.

Check that observed data exercises material predicates. A zero-row or unrepresentative fixture does not establish a production benefit. When permitted, compare equivalent variants on isolated synthetic data with the same relevant structure, settings and workload; report the synthetic boundary. Distinguish an index existing from the optimizer selecting it, and cache warm-up from a meaningful change in plan or performance.

For batch optimization, preserve the existing behavior, ordering, scope and per-item outcomes while measuring actual query or external-call counts. A faster aggregate that changes semantics is not an equivalent implementation. Report units, sample counts, actual plan evidence and uncertainty; do not create or remove a persistent index merely to run an unapproved benchmark.
