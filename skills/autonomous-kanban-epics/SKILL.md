---
name: autonomous-kanban-epics
description: Deliver an approved Kanban epic with readiness checks and scoped delegation.
---

# Autonomous Kanban epics

Use for owner-authorized execution of an epic or ready task group. Establish the exact execution and lifecycle limits, including any user approval required for `done`, before starting.

1. Read the complete candidates, dependencies, existing epics, and current source contracts. Classify each as ready, blocked, or carrying a hidden risk; a `todo` stage alone is not readiness. Organizational, historical, and reference cards are not implementation nodes.
2. Give the owner a concise plan covering task areas, dependency order, exclusions, verification, and any Git actions. Create or modify board records only within the approval already granted.
3. Delegate only when authorized and the required role or profile is available. Partition work by ownership and avoid parallel edits to shared files or contracts. Preserve explicit sequencing, profile, review, and commit requirements from the task rather than inventing an agent name or trailer.
4. Run the applicable checks and required independent review of the complete diff and call sites. For shell, CLI, or build targets with user-controlled values, test argument boundaries with hostile synthetic inputs, ensure they are passed as data rather than interpolated shell source, and verify command failures propagate nonzero even through later formatting. Repair confirmed in-scope findings in a separate corrective change when the project requires it, rerun affected checks, and repeat independent review to confirm previous blockers are resolved.
5. Follow the actual board lifecycle and acceptance gates. Keep the epic active until its required children are ready. Do not treat a child handoff as parent completion, or static evidence as proof of a live effect. Move to `done` only with explicit user approval; merge, push, deploy, and destructive actions require their own applicable authorization. Keep independently owned implementation and lifecycle changes separate, and never include another actor's staged changes in a commit.
6. Report actual checks, known blockers, current active work, uncommitted changes, and the next actionable node. Map unrelated findings to existing work before suggesting a new card, and honor any requirement for owner approval before editing it.

See [readiness and review](references/readiness-and-review.md) for audit and verification details and [artifact audit](references/thin-client-artifact-audit.md) when reducing a client or provider capability.
