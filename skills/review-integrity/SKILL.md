---
name: review-integrity
description: Independently review a candidate, acceptance evidence and cross-cutting behavior; ревью, проверка приёмки.
---

# Review integrity

Use for an independent review or acceptance decision, not implementation. Establish the request, review authority, required independence, exact candidate and relevant boundaries before inspecting. Record the current revision, staged/unstaged and relevant untracked work where authorized. When the tree may move, check candidate identity before relying on earlier evidence; a snapshot is not proof of runtime behavior.

Trace the actual behavior from producer and inputs through consumers, state transitions and observable effects. For cross-layer changes inspect shared wiring and the complete integrated range, not only each child verdict. For a prior finding, verify the current candidate and relevant regression; previous reviewer or implementer summaries are leads, not fresh results.

Classify observed defects, evidence gaps and hypotheses separately. State the trigger, affected boundary, impact and precise source or evidence. An unavailable required gate can block acceptance without being a proven product defect. Do not infer authorization to edit, stage, move a board card or publish from review alone. Run only permitted checks with side effects understood; preserve partial, failed and unrun results.

For requested negative guarantees, consult [negative contract review](references/negative-contracts.md). For exact final validation results, use [validation evidence](../validation-evidence/SKILL.md); use [verified findings](../verified-findings/SKILL.md) to assess a defect or test oracle. Give the requested verdict with actionable findings, evidence and limitations, without overstating untested behavior.

For backend reviews, use [backend boundaries](references/backend-boundaries.md). For cross-runtime configuration and session changes, use [integration boundaries](references/integration-boundaries.md).
