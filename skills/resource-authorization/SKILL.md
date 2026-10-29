---
name: resource-authorization
description: Secure resource, tenant and workspace ownership across API reads, mutations and replay.
license: MIT
---

# Resource authorization and isolation

Use when a caller selects durable or live resources, a project/workspace, tenant, session, account or credential-bearing connection. Authentication establishes caller identity; a supplied identifier or path is a selector, not proof of authority.

Trace each operation from the request or transport to trusted server-owned context, durable ownership, query/mutation, worker and response. Include list and detail, resume, search, counts, aggregates, exports, imports, live actions, cleanup and equivalent endpoints. Resolve and verify the current caller's grant and resource scope **before** sensitive reads, credential access, effects or mutations. Scope queries and captures at their source; filtering a global inventory afterward has already accessed foreign data. Fail closed when the required trusted context or ownership is unavailable.

Match identity comparison and canonicalization to the actual contract. Preserve durable ownership on an existing resource; do not silently reassign missing ownership or trust a request-supplied workspace. Ensure scope remains attached through internal projections, caching, multi-profile aggregation and fallback paths. Unknown/foreign resources must use the documented non-disclosing denial, without hiding required operational errors.

For implementation and regression tests, read [scope and isolation checks](references/scope-isolation.md). For credential selectors, idempotent replay and one-time download capabilities, read [credential and capability checks](references/credential-capabilities.md). For an independent read-only review, use [acceptance evidence](references/acceptance-evidence.md). Exercise the real authorization seam with an authorized positive control and foreign/missing/spoofed negative cases; verify forbidden history reads, credentials and effects do not occur. Preserve the project’s actual authorization and compatibility policy.

For browser-owned sessions and request-context bridges, read [browser session boundaries](references/browser-session-boundaries.md).
