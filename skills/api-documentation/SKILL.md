---
name: api-documentation
description: Repair and verify API contracts, OpenAPI artifacts, documentation UIs and public capability catalogs.
---

# API documentation

Use implementation, route and schema declarations as evidence for public claims. Identify the canonical source, generated artifacts, public surfaces, supported tools and authorized scope before editing. Preserve unrelated work and follow the project's actual conventions.

For API contracts, reconcile documentation with shipped routes, request and response shapes, authorization, entitlements and limitations. Change canonical inputs first, then regenerate only affected derived artifacts with the project's supported commands. Verify source and generated output for drift and stale claims; never assume a specific build target exists or hand-edit generated output as a substitute for fixing its source. Runtime-generated specifications need runtime verification.

For public API indexes, `llms.txt`, sitemaps and similar catalogs, use the [public capability catalog checklist](references/public-capability-catalogs.md). Reconcile counts, localized entries and boundaries against evidence; a catalog-only change does not by itself require OpenAPI generation, container builds or a commit.

For self-hosted documentation UIs, use the [UI asset checklist](references/self-hosted-docs-ui.md). Distinguish a page that makes no third-party startup requests, a build that does not download UI assets, and an entirely offline rebuild: these are separate claims.

For operation-level authentication metadata or a generator that cannot write to its default output, use [schema verification](references/schema-verification.md). Run proportionate, available project checks for the changed contract, including relevant authentication behavior and documentation drift. Report commands, actual outcomes and skipped checks; distinguish unchanged artifacts from regenerated changes. Preserve existing staged work and commit only when authorized under the applicable project policy.
