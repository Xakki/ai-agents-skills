---
name: security-acceptance
description: Independently review security boundaries, adversarial tests and current acceptance evidence.
license: MIT
---

# Security acceptance review

Use for an independent, read-only review of a claimed security repair or boundary contract. Freeze the authorized candidate and evidence scope, then map each claim to the real caller, trust boundary, forbidden effect and observable result. Protect unrelated work and secret or opaque data; use synthetic fixtures and approved runners.

Review the whole path, not only a helper: policy and authentication, resource authority, parsing, storage, runtime transport, output, cancellation and cleanup as applicable. A green broad suite does not override a reproduced defect, and an unavailable test is not a pass. Separate confirmed findings, fixture or environment blockers and untested claims.

Use [adversarial cases and credentials](references/adversarial-cases.md) and [artifact, recovery and integration evidence](references/artifact-and-recovery.md) when relevant. Report concrete location, trigger, observable impact and deciding evidence; do not edit, deploy, restart, access live credentials or force external calls under review-only authority.
