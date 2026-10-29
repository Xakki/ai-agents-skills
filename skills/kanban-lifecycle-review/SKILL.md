---
name: kanban-lifecycle-review
description: Review Kanban stage changes against card history, dependencies, and evidence.
---

# Kanban lifecycle review

Use for read-only review of a card's lifecycle or a status document that cites it. Capture the current source, branch, base, HEAD, affected paths, and repository status when applicable. Inspect the complete baseline-to-HEAD change, not only the last repair.

- Verify one canonical card and ID, its actual stage, any maintained status field, dependencies, acceptance criteria, and referenced cards. Do not infer completion from a directory name alone.
- Read the complete current card and its decisions and execution log. Identify active wording that contradicts later decisions, such as an unresolved promotion question or an obsolete instruction to remain in an earlier stage. Recommend marking superseded statements as historical with the resolving evidence, or removing redundant wording when authorized; retain unresolved future gates.
- Keep `ready` or a pilot handoff distinct from `done`, production rollout, rollback, and any other acceptance gates. Check that roadmap and status claims describe the actual verified endpoint rather than elevating it.
- Run the available read-only board and diff checks; distinguish current results from historical claims and report unavailable checks. A clean linter alone does not prove lifecycle consistency.
- Repeat the relevant final snapshot before the verdict. Classify findings by impact: a false completion or dependency claim that could bypass a security or production gate is high; conflicting path, status, or card text that can misdirect work is medium; stale wording with no active scheduling effect is low. Report each finding with its exact source, contradictory claim, current evidence, impact, and minimum correction. Do not edit, commit, or publish during a read-only review.

See [historical lifecycle wording](references/historical-lifecycle-wording.md) for the targeted review and evidence checklist.
