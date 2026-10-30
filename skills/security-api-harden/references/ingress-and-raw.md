# Ingress and generic protocol surfaces

Map framework parsing, authorization, scope, schema, persistence, queue, worker, response and logging. An ingress URL parser and a later DNS/redirect/egress control are distinct boundaries. Where URLs are admitted, specify accepted scheme, authority, userinfo, fragment/query, address representations, normalization and size; test parser edge cases against the actual runtime and prove the representation delivered to downstream policy. Follow the explicit contract rather than imposing one global URL policy.

For intentionally open RPC or generic method envelopes, authorize operations and resource identity independently of syntactic validity. Prefer a bounded, fixed registry over request-controlled dynamic import or evaluation. Apply the documented size, depth, node, string, request, queue and response bounds at the boundary where memory or work is consumed; a later result cap does not protect earlier parsing or storage. Ensure refused foreign IDs do not disclose resource existence where the contract forbids it.

Exercise allowed and denied roles, valid and malformed shapes, limits, privacy, stale or revoked grants and replay/cancellation with synthetic fixtures. Assert denial occurs before forbidden quota, persistence, logging or dispatch. Findings require the actual input-to-impact path; unexecuted concerns remain evidence gaps.
