---
name: kanban-acceptance-evidence
description: Record and verify acceptance evidence on Kanban cards without overclaiming.
---

# Kanban acceptance evidence

Use when a card's lifecycle or handoff depends on concrete acceptance evidence. Inspect the full card, approved criteria, source revision, owned scope, and existing evidence before editing.

Locate the actual repository and card; capture branch, HEAD, index, working-tree baseline, protected inputs and their observed filesystem metadata, and an explicit allowlist of records. Verify identifier and digest syntax without silently repairing invalid input. An approval with missing required checks is not acceptance: preserve the original review, obtain a separate correction from the same reviewer session where available, and rerun only missing or invalidated gates under the applicable routing policy.

For each criterion record the exact observation, source or command, relevant target and version, result, limitations, and any required independent review. Differentiate executed checks from carried-forward evidence, skipped or failed checks, and unmeasured live behavior. Do not convert an unavailable gate, a local fixture, or a previous candidate's result into a current production pass.

Preserve decisions and historical evidence; explicitly mark a superseded claim at its point of use. Keep secrets and private payloads out of cards and reports. Update only the authorized records, preserve unrelated changes, and verify the real card and evidence after any supported move.

For an append-only evidence update, freeze the original bytes and digest first, append a dated sanitized block at an exact anchor, inspect the complete diff, and compare the current original-length prefix with the frozen digest. Repair only demonstrated damage from verified original bytes; never adopt a damaged baseline or reconstruct redacted text. Keep the receipt separate from immutable review and packet snapshots. For security or public APIs, explicitly exclude credentials, tokens, raw IPs, headers and bodies.

Promote only when the destination's actual criteria and authority are met. `ready` is not `done`, a child acceptance is not parent acceptance, and local checks do not authorize merge, push, deployment, or data deletion. Report the exact remaining conditions and owner when a criterion is unresolved.

Run the sanctioned board linter on the exact active card where supported; otherwise inspect its aggregate selection, verify the card is included and the checked count is nonzero, and report the actual scope. Separate historical-stage inventory collisions from the linter's own exit, errors and warnings; a successful active-only check does not prove historical uniqueness. If the linter excludes `done`, capture the active result before moving; if needed, validate the exact committed card and lock in an isolated temporary board and label this a copy-based check.

Preserve the index unless staging or a commit is explicitly authorized. For an authorized card-only commit, stage the final evidence body even after a mover staged its rename, inspect the entire cached diff and allowed old/new paths, and follow the repository's message policy. Verify native commit result, parent and SHA, content, history, index, and applicable post-commit checks. See [accepted evidence checklist](references/accepted-evidence-checklist.md).
