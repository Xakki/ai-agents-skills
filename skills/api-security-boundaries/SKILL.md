---
name: api-security-boundaries
description: Secure or review API ingress, transport, identity and response failure boundaries.
license: MIT
---

# API security boundaries

Use when API input, external calls, generic protocol methods, or responses cross a trust boundary. Trace real authentication, resource scope, validation, planning, transport, parsing, output and state effects. Separate a read-only review from an authorized implementation; neither implies live provider calls or deployment.

Validate at each relevant boundary before the associated side effect. Treat injected transport results and their inspection as untrusted where the contract requires it. Preserve stable, bounded and non-sensitive failure behavior; an error helper can leak a body before a later sanitizer runs. Authenticated callers still need the appropriate resource authority.

Select [ingress and raw APIs](references/ingress-and-raw.md), [transport and response validation](references/transport-and-response.md), or [generated and identity acceptance](references/generated-and-identity.md) for the active mode. Test actual consumer seams and observe forbidden downstream calls, with valid positive controls. Report missing coverage and live-runtime evidence separately.
