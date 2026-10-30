# Verification modes

## Long-running gates

Use the approved command unchanged; track the actual process and its completion or timeout. Capture full failure categories and final exit status rather than inferring success from a tail or process launch. Protect retained output according to its sensitivity. Check relevant workspace and index state afterward.

## Runtime and shared state

When readiness is requested, distinguish intended configuration or a clean source diff from the actual running artifact. Inspect the authorized runtime through supported interfaces and report observed versions, readiness and limitations. Do not restart or deploy during a read-only review. Databases, generated manifests, caches, snapshots and images can be shared mutable test state; serialize checks or use verified isolated fixtures. A fake external command is effective only if every downstream helper uses it.

## Changed contracts and repair validation

For an interface change, identify actual implementations, consumers and test doubles; use the relevant runtime and static checks. For a repaired regression, separately report the focused scenario, any required aggregate tests, and shared-state or integration gates justified by risk. Do not attribute a failure to changed code solely because it occurs in the same suite; retain exact evidence and label uncertain causes.

## Report

Record candidate identity, stage and worktree state before/after, exact command and cwd, outcome/exit code, applicable counts, named failures, effects, unrun checks and limitations. Summarize direct, baseline and environment evidence separately and avoid printing secrets.
