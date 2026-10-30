# Integration and session review boundaries

For cross-runtime or configuration changes, identify the actual producers, consumers, resource resolution order and lifecycle. Verify every relevant entrypoint uses the intended candidate; a helper that returns a resource does not prove that a running consumer loads it. Examine duplicate registrations, cache invalidation, process restart and version boundaries where they matter.

For session or project isolation, trace creation, lookup, list, resume, history and metadata access under the actual owner scope. Check missing, ambiguous or foreign scope inputs and the full caller chain; a scope parameter in a signature is not proof that every caller enforces it. Validate negative access claims using an authorized and observable boundary.

Report source, fixture and runtime evidence separately. Do not claim absence of leakage from a clean diff, configured setting or one passing path when other relevant consumers were not examined.
