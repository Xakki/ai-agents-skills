# Merge parent and generated-artifact evidence

Use when reviewing a completed merge or resolving a conflict with project policy. Pin the merge commit and each parent; verify actual parentage, affected files and merge bases. Compare each parent separately to the candidate, tracing the tests and contracts both sides intended to preserve. A marker-free diff is not proof of behavioral integration: marker-like lines can also occur legitimately in documentation or fixtures, so inspect context.

For each conflict, distinguish disjoint compatible changes, a genuine design choice and superseded behavior. Select a whole side only where the owning policy requires it; preserve compatible intent and record unresolved choices. Change canonical source before regenerating derived artifacts with the project's existing tools; do not edit generated checksums to satisfy a verifier.

Run proportionate sanctioned tests and validation for each affected contract, using the runtime actually needed by the repository. Report exact outcomes and explicit skips; a failed or unavailable independent gate is not a pass. If a merge commit is authorized, verify no unresolved entries remain, the entire staged candidate matches scope, and the final commit has the intended parents. A read-only review does not authorize a merge, commit or publication.
