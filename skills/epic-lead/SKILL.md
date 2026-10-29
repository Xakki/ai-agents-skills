---
name: epic-lead
description: Coordinate one approved Kanban epic through scoped execution, review, integration and authorized handoff.
---

# Epic lead

Coordinate one approved epic and its approved children. Resolve the active
board, its lifecycle and required project instructions before action; consult
[Kanban](../kanban/SKILL.md), [Git workflow](../git-flow/SKILL.md), and, when
using delegation, [team lead](../teamlead/SKILL.md). Their examples do not
supersede the user's scope, repository rules or runtime capabilities.

Record the epic identity, approved children, dependencies, acceptance criteria,
baseline and relevant risks. Do not start a later EPIC or expand scope without
authorization. Preserve unrelated changes and staged content; establish a clean
baseline only when the applicable project workflow requires one, without
resetting, stashing or discarding others' work.

For each finalization action, accept explicit user approval at hand-off,
recorded EPIC-scoped upfront autonomous authorization, other recorded upfront
task/workflow authorization, or recorded profile/agent authorization only if
applicable policy accepts it and it covers the exact target and action. Record
its source and scope. A grant for one action does not imply another, scope
expansion, or a tests/review bypass. Do not request another user confirmation
when a valid grant already applies. If the user or project requires explicit
confirmation for `done`, obtain it for that action.

## Prepare and execute

1. Resolve the actual project branch and board policy. Record the base identity;
   create or select an epic branch only when the task or project requires it.
   Do not assume a branch name, model, trailer or global clean worktree.
2. Map child dependencies, permitted paths, ownership, acceptance gates and
   integration boundaries. Parallelize only when authorized, dependencies allow
   it, and concurrent writes can be isolated or coordinated.
3. Delegate bounded work when the user, runtime and applicable policy require or
   support it. Use the available delegation interface and inherited defaults;
   select models or profiles only when explicitly required. If a required role
   is unavailable, report the blocker rather than silently substituting one.
   Otherwise, perform authorized implementation directly when appropriate.
4. Follow the actual lifecycle and QA requirements. Make or request independent
   read-only review when required or useful and available; report if a required
   review cannot be obtained. Repair confirmed in-scope findings with bounded
   retries and re-run affected evidence; stop if a required gate fails or a
   decision or scope change is needed.
5. Record concise results, relevant authorizations, review/gate evidence and
   verified commit identities where applicable. Keep prompts, credentials and
   secret-bearing output out of cards and logs. Follow project commit-message
   and trailer policy; never add evidence as Git trailers by default.

## Integrate and finalize

Integrate only the approved children and verify their real combined behavior,
including the full project quality gate when required by the applicable
workflow. A ready checkpoint does not itself authorize a final action. Perform
`done`, merge, push and deploy only with each action's valid authorization and
all applicable gates; where parent-before-child is required, preserve that
order. If a required grant, review or check is absent, retain the current state
and report the exact blocker.

Apply branch merge, archive or deletion only when the actual project policy and
the corresponding authorization permit it. Verify each authorized Git result
and preserve unrelated work. For an authorized push or deploy, read back the
exact target when the workflow requires it and report what was actually
observed. A local pass is not proof of publication or deployment. Hand off the
card states, changes, evidence, pending risks and any deferred actions.
