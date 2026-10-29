# Dependencies and scope planning

Use when a plan spans dependent cards or must be independently reviewed.

- Trace each prerequisite in both directions: the prerequisite states what it supplies and when, and every consumer names the required output and gate. Check the graph for missing owners, ordering conflicts, cycles, and consumers incorrectly admitted before their prerequisite is available.
- Map source contracts and integration boundaries before splitting work. Prefer a verifiable vertical slice when it provides a useful outcome without violating real ownership or ordering constraints; do not split solely to produce an architectural sequence.
- Reconcile every proposed item against the current board as now, merge, defer, freeze, removal candidate, or owner decision. Record rationale, dependencies, and where unique acceptance criteria go. An item proposed for deletion stays until that specific action is authorized.
- Distinguish implemented code, behavior demonstrated with injected test dependencies, normal application startup, and live rollout. A passing injected fixture cannot alone establish normal wiring or live behavior.
- If independent review is requested or required, finish and freeze the draft, identify its evidence and boundaries, and allow the reviewer to challenge scope, priorities, missing acceptance and the plan itself. Record the actual verdict and resulting decisions; an author completion is not independent acceptance.
- For read-only discovery, inspect board paths, aliases, counters, stage membership and prior decisions without allocating IDs or mutating cards. An absent tracker connection is an evidence gap, not a reason to invent a card's contents. Explain external concurrent changes rather than restoring them automatically.
