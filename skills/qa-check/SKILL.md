---
name: qa-check
description: Use before completion for autonomous project quality gates.
user-invocable: true
---

# qa-check

A quality gate to run **before** declaring a task done. Discover sanctioned
checks from project instructions, Make targets, manifests and scripts, CI
workflows, and saved project guidance. Scope checks to task-owned changes and
report Pass/Fail with truthful evidence.

Git mechanics follow the [git-flow](../git-flow/SKILL.md) core; this skill only
adds the gate behaviour below.

## How to run

1. **Discover before execution.** Read applicable `AGENTS.md` and project
   guidance; inspect sanctioned Make targets, manifests/scripts, CI workflows,
   and saved project-specific QA instructions. Use these sources to identify
   commands and path coverage. Do not ask a first-use questionnaire or guess a
   command, target, or test filter.
2. **Scope and run.** Identify the task-owned diff and select checks covering
   those paths. Use required Make/container gates when project instructions
   require them; otherwise use documented project-native runners. Broader
   regression checks are appropriate when project requirements or material
   blast radius justify them, without routine user confirmation. Do not assume
   a `name=` filter exists. Use only authorized, documented environment setup;
   do not install ad-hoc dependencies or bypass sanctioned runners. If essential
   command/scope information remains unclear, make reasonable read-only
   discovery and independent checks first; only then
   report a genuine blocker.
3. **Report each check.** Green requires exit status `0` and no new warnings
   under the project's stated policy. Red means report the failure and, when
   authorized and in scope, fix the root cause and rerun. Distinguish checks
   not run, blocked, failed, and passed; do not imply broader coverage than
   measured.

## Anti-patterns — never do these to make it "pass"

- Do NOT skip or disable lint / type checks.
- Do NOT mark tests skipped (`@pytest.mark.skip`, `.skip`, `xfail`, commenting
  out) without a real, stated reason.
- Do NOT use `--no-verify`, and never silence failures with `|| true` or by
  discarding stderr.
- Do NOT run a whole suite by default when a sanctioned focused check suffices;
  use broader regression checks when required or justified by material risk.
- Do NOT substitute a native runner for a required Make/container gate or
  invent a targeted filter to avoid a sanctioned gate.
- Green checks alone are not authorization; when valid action-specific
  authorization covers the target and all gates pass, automated merge, push,
  or deploy is allowed without a redundant confirmation.

## Authorization boundaries

Passing QA checks is not authorization to publish, merge, or deploy. Such
actions require valid action-specific authorization covering the target and
all required gates. Never infer authorization from a green check or silently
perform a protected action; preserve any applicable approval requirements.
