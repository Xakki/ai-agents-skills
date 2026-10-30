# Browser-backed session boundaries

Use when a service owns or reuses an authenticated browser session, profile or
an ephemeral browser-to-transport context. Resolve the real authentication and
profile policy from the task: shared identity and separate profiles have
different implications; do not silently switch between them. Treat profile and
session artifacts as credentials, not ordinary test fixtures.

Inventory every runtime, login, refresh and recovery entry point, including
implicit defaults. Classify owned persistent, explicitly shared and disposable
sessions from actual resolution and lifetime locking. A process, profile path,
lock artifact, successful detached launch or active port alone does not prove
ownership, readiness or authentication. Require the documented current
owner/lease and, where relevant, bound socket and process identity. Unknown
ownership blocks takeover; read-only diagnosis does not authorize login,
refresh, process termination, lock removal or profile mutation.

Hold the appropriate shared profile lock throughout the owned browser lifetime,
including startup, refresh and cleanup. For authorized migration, protect both
source and destination against races, refuse conflicting targets, preserve
unrelated profiles and establish recovery before mutation. Apply the actual
platform's filesystem and process-identity safeguards; if the browser accepts
only a pathname, document residual replacement risk rather than claiming a
verified file descriptor binds its later open.

For an explicitly authorized context bridge, trace its exact producer and
consumer. Bind origin, operation, path, owner and short lifetime as required by
the actual contract; allowlist only necessary metadata, bound sizes, avoid
persistent/global state, and keep credentials and content out of diagnostics.
Protect security-sensitive destination headers against accidental overlay.
Invalid or stale context must fail before browser or transport effects. Test
wrong identity, cross-session isolation, concurrent acquisition, cancellation
and cleanup with synthetic inputs; distinguish offline seam proof from a
separately authorized live capture and delivery.
