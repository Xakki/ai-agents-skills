---
name: ipc-authority
description: Validate peer authority, framing and fail-closed broker IPC boundaries.
license: MIT
---

# IPC authority and framing

Use when a broker, private protocol or local adapter makes decisions based on observed peer identity or an approval verifier. Separate caller input, actual peer observation, internal authority policy, framing, durable state and transport. A caller-provided expected peer or project selector is not an authority source. Enforce the policy at every public operation before verifier, durable mutation or external action.

Define the protocol's actual version, fields, sizes, operation set, canonicalization and error contract; do not impose byte-level canonical JSON when the protocol does not require it. Reject malformed, stale, mismatched or ambiguous requests and untrusted verifier results according to the contract. Validate types before attacker-controlled comparisons, serialization or arithmetic; apply language-specific protections where relevant.

Use synthetic fixtures for wrong-but-valid peers, forged or mutated values, duplicate or unknown fields, bounded frames, verifier failure, replay and no forbidden downstream calls. A same-process fake peer proves only that seam; it does not prove OS credential provenance, deployment or real socket authentication. Those require separately authorized adapter and runtime evidence.

In-process visibility, private names or immutable objects alone are not a security boundary against hostile code in the same process. When actual external effects require stronger authority, establish it at an independently authenticated process or service boundary supported by the threat model. Keep a purely synthetic implementation explicitly separate from that runtime claim.

For a local socket, authenticate observed peer credentials against the actual policy; when it specifies approved identity pairs, independent user and group lists can create unauthorized combinations. Bound the complete frame and response, reject duplicate or extra requests when the contract requires exactly one, and dispatch only after authorization and strict validation. Keep endpoint paths server-controlled and, on cleanup, remove only the socket instance the server created. Where a response is bound to a mutable owner marker, revalidate its relevant contents and endpoint identity across the exchange; inode equality alone cannot detect in-place mutation.
