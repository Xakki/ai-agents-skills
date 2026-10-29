---
name: delivery-loop
description: Implement scoped software changes, verify them and report evidence; deploy only when authorized.
---

# Scoped delivery loop

Identify the requested outcome, scope, project instructions, affected boundaries and acceptance criteria. Inspect existing relevant code and preserve unrelated staged, unstaged and untracked work. Implement the smallest justified change that addresses the user's goal rather than extending scope because nearby changes are convenient.

Run checks proportionate to the change and any required project gates. Record actual results, skipped checks and limitations. Small reversible changes need not gain tests that merely mirror the implementation; add meaningful regressions when risk or the requested workflow warrants them. Follow the project's supported interfaces and do not conflate local verification with live runtime acceptance.

Arrange independent review, commits, publication, deployment or external messages only when requested or otherwise authorized. A successful local test does not grant authority to perform these actions. Continue already-authorized work across intermediate status requests, and report the outcome and remaining blockers clearly.
