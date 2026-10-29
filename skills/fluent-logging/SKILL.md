---
name: fluent-logging
description: Configure and verify structured logs and Fluent Bit delivery for the project's selected logging stack; логи, сбор логов.
---

# Structured logging and Fluent Bit

Inspect the project's existing logging contract, selected collectors, deployment configuration and authorized destinations before making changes. Use its documented integration interface; do not assume a particular package, vendor, host or log backend. Preserve existing fields, severity semantics, retention and access controls unless the task authorizes changing them.

Emit structured records where the project supports them, use stable fields, and avoid logging credentials, session material or unnecessary personal data. Check URLs, exceptions, HTTP traces and request bodies for inadvertent secrets before emission. Treat high-cardinality fields according to the actual storage and indexing design. Define how the service behaves when a sink is unavailable from the project's reliability and audit requirements; do not silently impose best-effort or fail-closed behavior.

When the project already selects the specific Fluent Bit integration documented in [integration.md](integration.md), consult that reference as a conditional example and verify its assumptions against the selected versions and environment. The historical [logging rules](rules.md) and [Python example](python.md) are project-specific examples, not universal policy. Do not add their dependencies, configuration or deployment steps without authorization and evidence that they fit.

Verify the actual pipeline end to end with an authorized synthetic marker: application emission, collector routing and searchable destination. Report whether each boundary was observed; successful local output alone does not prove delivery. Container driver or collector changes can require service recreation, so identify the project's maintenance and recovery procedure before applying them.
