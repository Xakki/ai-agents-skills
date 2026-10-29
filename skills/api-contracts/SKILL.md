---
name: api-contracts
description: Implement or review API request, response and serialization contracts across real boundaries.
license: MIT
---

# API contracts

Use for a new or repaired API operation, a consumer validator, or an independent review of producer-to-consumer wire behavior. Establish which of implementation and read-only review the request authorizes; review does not authorize edits, deployment or live probes.

Trace the actual route, composition, request schema, validation, authorization/entitlement, client, serializer and response consumer. Resolve the documented contract from the authoritative source and implemented producer; do not infer it from an example, generic standard name, stale review or convenient fake. Define positive and negative behavior for each outcome and preserve existing security and compatibility rules. Keep project-specific route names, framework and toolchain choices in their own instructions.

For delivery and tests see [integration and offline verification](references/integration-and-tests.md); for structured responses and pagination see [producer and consumer validation](references/response-validation.md); for health-backed APIs see [health evidence](references/health-api.md). Use the project's sanctioned schema generation only when the affected source requires it; a generated artifact is not the canonical source by default. Run proportionate focused gates and report actual results and limits.
