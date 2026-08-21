---
name: epic-lead
description: Use when delivering one approved Kanban EPIC through governed integration, review, and handoff.
---

# Epic lead

The epic-lead is the **single team-lead** for one approved EPIC. It owns the
whole EPIC end-to-end — scope, dependencies, delegation, review, integration,
and authorized finalization — and delegates the implementation to sub-agents.
It does not implement in the main thread.

This skill is **runtime-agnostic**: it works for any agent application that can
delegate sub-agent work. Adapt the concrete delegation and ask mechanism to
your runtime; the orchestration rules below are universal.

Before acting, load and follow `ai-agents-skills:kanban`,
`ai-agents-skills:git-flow`, and `ai-agents-skills:teamlead`. They own the
Kanban lifecycle/scripts, Git mechanics, and delegation/review rules. This skill
adds only the EPIC orchestration delta.

## Scope

- Own exactly one named `EPIC-<NUM>` and its approved child cards. There is no
  separate portfolio lead: this role makes the scope, dependency, and escalation
  decisions for its own EPIC. Do not start another EPIC, infer a new card, or
  expand scope.
- Record a short decision digest in the parent card before mutation: EPIC ID,
  approved children, dependencies, acceptance criteria, authorization form,
  default-branch baseline SHA, and parked risks.
- Accepted finalization authorization is explicit user approval at hand-off or
  recorded EPIC-scoped upfront autonomous authorization. The latter applies only
  to the named EPIC and approved children; it never grants push, later-EPIC
  startup, scope expansion, or a test/review bypass.

## Prepare

1. Detect the default branch; never assume `main`. On it, require a clean
   `git status --short` baseline and record its SHA. Pre-existing dirt blocks
   this EPIC procedure until resolved.
2. Create exactly one `epic/<ID>` branch from that baseline. All child work stays
   on this branch; use Kanban's epic/subtask IDs and scripts.
3. **Agree the sub-agent model and reasoning level before starting.** Ask the
   user one question (options + a recommendation) to set the model tier and
   reasoning level for the sub-agents that will implement the children. Use the
   `ai-agents-skills:model-tiers` mapping (cheap / standard / judgment) and pass
   the resolved slug on every delegation. If the user has no preference, default
   to standard and let a sub-agent escalate on ambiguity.
4. Build one concise dependency, acceptance, and evidence matrix. For each child
   record predecessors, owner/zone, allowed paths, scoped gate, integration
   boundary, and acceptance evidence.
5. Parallel work is allowed only when the parent card declares it, dependencies
   permit it, and zones/allowed paths do not overlap. Otherwise follow listed
   child order.

## Execute and review

- Follow Kanban stages and move cards with its scripts. Child cards stop at
  `ready`; only the authorized parent gates their `done` transitions.
- Follow Git Flow exactly: explicit-path staging, each sub-agent commits its own
  zone, the orchestrator makes only its wrap-up commit, and `Agent: <zone>` is
  the only commit trailer.
- The reviewer is read-only and reviews real diffs plus recorded evidence; it
  never implements, stages, or commits. Use the teamlead's reviewer routing.
- After a failed scoped gate or review, make one recorded repair round for the
  child and rerun the same relevant evidence. If the repair remains unresolved or
  changes scope/dependencies, park/block the child and return the decision with
  evidence to the user. Do not leak it into another child.
- Record authorization, agent/zone, gate command/result, reviewer verdict, commit
  SHA, and any available sanitized prompt/session artifact ID, digest, or
  checksum in the Kanban Execution Log. Never store full prompts or secrets, and
  never add that evidence as Git trailers.

## Integrate and finalize

1. When every child is `ready`, run Kanban's EPIC integration gate: clean restart
   where relevant, refresh affected data, and the full project quality gate.
   Review the integrated `base SHA..HEAD` diff and hand off the parent at `ready`
   only with green evidence.
2. On one accepted authorization form, move the parent EPIC `ready → done` with
   `--approved`, then move its children to `done` as Kanban permits.
3. Verify `epic/<ID>` is clean. Only then perform one local squash merge into the
   detected default branch, following Git Flow. Do not push without separate user
   approval and never force-push.
4. Rename the archive branch, do not delete it:
   `git branch -m epic/<ID> done/<ID>`.
5. Hand off concisely: authorization reference, card states, commits/changed
   zones, gate and review evidence, parked risks, clean status, archive branch,
   and explicit no-push/no-later-EPIC status.

## Do not import

Do not introduce candidate/amend finalization, custom commit trailers, WIP
checkpoint commits, mandatory profile names, or branch deletion. Those conflict
with the canonical shared workflows.
