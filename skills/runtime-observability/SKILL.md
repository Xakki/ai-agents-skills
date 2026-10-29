---
name: runtime-observability
description: Design or diagnose telemetry delivery, storage and dashboards using observable runtime evidence.
---

# Runtime observability

Identify the question, scope, source, telemetry type, available interfaces, intended audience and permitted observations. Trace the actual boundary from instrumentation through transport, collection, storage, query and display. A configured exporter, accepted transport response, indexed record, query result and rendered dashboard are distinct facts. Isolate the first unverified or failing boundary before changing a live system.

Define units, timestamp, identity, aggregation, freshness and missing/unknown semantics for the actual data contract. Preserve privacy through a bounded field policy, appropriate retention and redaction at the final output; do not expose credentials or raw payloads in examples or diagnostics. Avoid treating missing data, a failed query or a display gap as a measured zero.

Validate using existing data or appropriately scoped, authorized synthetic events and read back the relevant stored result where the task requires delivery proof. Distinguish test-only fixtures from real workload and live acceptance. Source changes, collector activation, dashboard publication, alert routing and notifications require their own authorization and supported runtime interface.

For delivery and aggregation pitfalls, read [telemetry evidence](references/telemetry-evidence.md). For dashboard design and readback, read [dashboard operations](references/dashboard-operations.md). Use [systematic debugging](../systematic-debugging/SKILL.md) for the underlying failure investigation.

For an explicitly requested persisted request audit trail, read [audit trail boundaries](references/audit-trail-boundaries.md).
