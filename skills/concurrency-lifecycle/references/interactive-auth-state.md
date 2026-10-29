# Authenticated interactive state and async work

Use when an interactive client fetches or mutates owner-scoped data while
identity, session, navigation or active view can change. Resolve the current
principal and authorization at the real boundary; a request started under an
old identity must not publish a response, error or finalizer into a new session.

Capture an authentication generation and operation identity at every async
boundary. When different operations write the same collection or view, also
coordinate a shared mutation/version fence; independent per-operation counters
alone cannot prevent a late list, update or error from overwriting newer state.
On owner switch or authorization loss, synchronously prevent old-owner content
from rendering, invalidate pending generations, clear sensitive transient
fields and apply the project's documented state-reset behavior. Guard failure
and cleanup callbacks as well as success paths.

For refresh queues, preserve owner association across queued calls, refresh,
retry and failure. Test owner changes while waiting, overlapping expiry,
late errors, retry failures and eventual settlement of all waiters; do not
replay one principal's request under another principal's refreshed authority.
Project incoming objects to permitted fields and avoid persisting or logging
transient secrets. Test the actual client behavior with synthetic deferred
responses and controlled interleavings, including forbidden writes and an
allowed positive control. A client-only harness does not prove server-side
authorization or integrated session behavior.
