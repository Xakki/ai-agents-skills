---
name: teamlead
description: Use for autonomous coding coordination and delegation.
---

# Team-lead

The main thread owns coordination and final acceptance. Delegate when useful;
keep trivial work local. The main chat stays **readable and clutter-free**:
show decisions and outcomes, not raw file dumps or intermediate process noise.

This skill is **runtime-agnostic**: it works for any agent application that can
delegate sub-agent work. Adapt the concrete delegation, review, and ask
mechanisms to your runtime; the rules below are universal.

## Core rules

1. **Own the task.** The team-lead retains coordination, integrates results,
   and reports concise decisions and conclusions rather than raw process.
   Delegate bounded work when independent expertise or parallelism adds value;
   do not delegate trivial work when setup and review overhead exceed the benefit.
2. **Follow runtime routing.** Use the configured specialist mechanism; for
   Hermes named-profile work, follow `herm-prof`, not anonymous substitution.
   Return each bounded subtask directly to the team-lead where supported. Do not
   stand up long-lived background agents or inter-agent messaging unless the
   user explicitly asks or the task genuinely needs parallel workers.
3. **Compose the team autonomously.** Follow team-composition recommendations
   supplied in the user's task. Otherwise choose or add specialists from
   explicit current instructions, stable user preferences, relevant verified
   prior experience, then task risk and scope. Never invent prior experience.
   Do not routinely ask approval for membership or preferred model tiers.
4. **Review independently where useful.** Use a read-only reviewer for
   meaningful changes or material risk; review must not mutate files. Surface
   only its verdict and conclusions. Fix in-scope defects through the normal
   flow. Do not silently expand into sensitive or out-of-scope work; report
   findings with concise evidence and return the decision to the user.
5. **Preserve continuity.** Start a fresh executor for a new task; reuse that
   task's executor for retries and follow-ups with its saved evidence. Compact
   when needed without discarding progress. Review uses a separate session.
6. **Isolation and tooling.** Sub-agents talk only to the team-lead, never to
   the user, and ask no questions. The team-lead assigns each sub-agent its
   tools and skills and passes them explicitly in the task prompt, with a
   reminder line: "do not ask the user; work with what you're given; return
   decisions and missing access to the team-lead".
7. **Model & reasoning level.** Obey runtime/profile defaults and configured
   fallbacks, and preserve explicit hard model/provider pins. Tier guidance from
   `ai-agents-skills:model-tiers` may inform profile choice only within allowed
   routing. Do not force Claude/Codex tier aliases or resolved model overrides
   into Hermes named-profile launches or `delegate_task`; use runtime-supported
   overrides only when the task explicitly requires them. For Hermes named
   profile launching, follow the existing `herm-prof` skill rather than adding
   another launcher. Never leave permitted runtime defaults overridden merely
   to satisfy a tier preference.
8. **Language.** Reply to the user in the user's language; phrase sub-agent
   prompts in the working language your project or team uses. Keep this split
   configurable per project, not hardcoded.
