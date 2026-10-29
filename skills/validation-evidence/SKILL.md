---
name: validation-evidence
description: Record final or post-repair validation, including exact check outcomes and residual limitations.
---

# Validation evidence

Use for a requested final or post-repair validation pass. Establish the actual project, candidate, current inputs, authorized scope and applicable required gates. Record relevant branch and revision, staged and unstaged changes, and untracked deliverables before and after; ordinary Git diff checks do not include untracked files.

Discover and use the project's supported entrypoints and working directory. Inspect a command's side effects before calling a pass read-only: tests may start services, modify generated files or shared state. A read-only authorization does not authorize edits, index changes, service startup, mutation or deployment. Run only permitted checks, state any missing authorization or environment blocker, and do not perform a repair in an independent read-only review.

Record each exact command, working directory, exit status, meaningful totals and failures. A launched or timed-out process is not a completed gate; track its actual completion when supported. Avoid concurrent tests that share mutable state. Separate earlier evidence from checks performed on the present candidate and label unrun checks. For long-running, shared-state or runtime checks use [verification modes](references/verification-modes.md).

For a repair, verify the original failure with focused checks where feasible, then required broader gates and proportionate integration checks where shared state or ordering matters. Do not automatically require every suite. Classify observed direct, baseline and environment failures separately; a mixed gate can contain several categories. A wrong invocation or working directory is an operator error, not a product result. Do not infer a root cause without evidence.

Report the candidate, commands and outcomes, relevant counts and failures, worktree effects, untested scope and blockers. A passing subset is not the whole gate. Distinguish self-check from independently authorized review. For defect and mutation evidence, see [verified findings](../verified-findings/SKILL.md).
