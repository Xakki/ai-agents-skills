---
name: evidence-backed-kanban-delivery
description: Deliver measurement-backed Kanban work with reproducible evidence.
---

# Evidence-backed Kanban delivery

Use when a card's acceptance depends on measurements or benchmark results. Preserve prior evidence and record the precise scope of new observations.

1. Capture repository, branch, baseline and relevant staged, unstaged and untracked state. Read the complete card, acceptance criteria, required source revisions, and owned paths; preserve unrelated state. Inspect the measurement harness, units, arguments, sample counts, aggregation, error handling, and cleanup before relying on its output.
2. Run only authorized measurements and checks. Record exact parameters, raw samples, units, sample count, cadence, aggregation method, and observations; distinguish a local or reduced synthetic run from historical, production, or full-scale evidence. Do not equate a fake service check with a real workload measurement. When feasible, perform a current real local harness spot-check without replacing historical multi-trial evidence.
3. Verify calculations and edge cases, including zero samples and invalid units, with focused fixtures when applicable. Ensure the test distinguishes the claimed behavior from basic reachability and fails if prerequisites fail.
4. Report actual task gates, unrelated failures, skips, and unmeasured claims without converting failure into a pass. Apply the project's authorized adjacent board transitions and lint checks before and after a move, require evidence for the selected stage, and preserve unresolved acceptance gates. Reconcile maintained status fields with the actual path; do not invent missing fields.
5. Stage and commit only when authorized, with exact owned paths and the actual message policy. A helper-staged rename may lack later evidence edits: inspect and refresh the final body when staging is authorized. Verify the resulting card, revision, message, evidence, index and excluded changes; report only the cleanliness and source ancestry that were observed. Recompute ahead/behind after the last commit or report exact refs instead.

Use [measurement evidence](references/measurement-evidence.md), [lifecycle and handoff evidence](references/lifecycle-and-handoff-evidence.md), and [read-only readiness review](references/read-only-readiness-review.md) for the relevant mode. `ready` is not `done`; explicit user approval is required for `done`.
