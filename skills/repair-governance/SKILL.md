---
name: repair-governance
description: Coordinate repeated repair and review attempts while preserving scope, evidence and actual authority.
---

# Repair governance

Use when a repair repeatedly fails the same gate or review and another iteration is being considered. Reconcile the current candidate, actual failing boundary, existing work, required gates, authority and any user-directed stopping point. Identify whether the failure concerns setup, test discovery, permissions, application behavior, assertion, shared state or cleanup before choosing another attempt.

Preserve successful evidence for unchanged inputs and use the same executor when appropriate and supported; do not replay completed effects or restart a still-running worker. Give each bounded attempt a concrete hypothesis, scope and observable result. Honor applicable budgets and retry limits; do not assume a runtime can switch model, profile, timeout or reviewer. If a required role is unavailable, block only dependent work.

After a real repair, run the affected checks and required independent review against the final candidate. Distinguish a documented acceptance change authorized by the owner from a weaker gate chosen to produce a pass. Report prior failures, current outcome, residual uncertainty and next action. Stop or escalate when the actual instruction, budget, authorization or unresolved blocker requires it.
