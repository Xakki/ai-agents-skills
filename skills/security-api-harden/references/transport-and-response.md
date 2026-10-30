# Transport and response boundaries

Validate requested transport plans before side effects and verify the actual permitted adapter is used; do not silently bypass a required gateway. Apply the intended route, timeout, retry and redirect policy. Treat result shape, fields and even potentially hostile object inspection as boundary inputs; map malformed or exceptional responses to bounded sanitized outcomes without exposing raw payloads or credentials.

Where the caller's response-privacy contract forbids reading error bodies, classify status before any generic helper that parses or formats them. Test non-success as well as success, streaming and non-streaming where relevant, retry and logging paths, and payload-bearing exception chains. A test of the final sanitizer alone cannot prove earlier layers did not read or expose data.

For HTTPS and proxy tunnels, verify distinct proxy and target identities, trust and redirect policy at the actual socket/client boundary. Use certificates and fake endpoints that cannot accidentally validate the wrong peer; reject a mismatched peer before forbidden downstream calls. Do not disable certificate verification to diagnose a failure. Synthetic tests prove their tested setup, not a live daemon's loaded configuration.

When an outbound policy requires pinned public addresses, validate and bind both upstream proxy and destination at each connection or redirect as required; a validated DNS answer is not proof that a remote proxy actually contacted that address. Keep the original hostname for the corresponding TLS/HTTP identity where the protocol requires it, and distinguish proxy-handshake errors from target responses. A hostile proxy cannot itself prove the final peer without trusted observation. Bound framing and decoded/wire sizes before storage, and recheck durable source authorization at the actual dispatch fence.

For origin-scoped credentials, inventory all construction and request paths,
including inherited helpers, metadata discovery, redirects, retry/fallback and
caches. Bind each credential to the intended origin and authority before use;
an ingress credential is not automatically an upstream or relay credential.
Scope reusable caches to the authorization and identity dimensions that affect
results, and test that a change of identity cannot reuse another scope's data.
