---
name: git-flow
description: THE shared git core every other git-using skill follows — commits, branches, push, merge, PR, force-push. Use whenever git work happens. Триггеры RU — «закоммить», «коммит», «ветка», «пуш», «смержить», «пулреквест», «форс-пуш»; EN — commit, branch, push, merge, pull request, force-push, rebase.
---

# git-flow — shared git core

Single source of truth for how agents do git in this plugin. Other git-using
skills (kanban, schedule-tasks, prepare-pr, qa-check, git-move) follow this CORE
and document only their own context-specific deltas. Edge cases and longer
examples → [reference.md](reference.md).

## CORE rules

1. **Default = commit to the default branch.** An agent commits its work
   directly to the default branch; the user reviews via commit history. Create a
   `feature/`·`fix/`·`chore/` branch **only** when the user explicitly asks, OR
   when another skill defines its own branch model (kanban does — per-task
   `task/<ID>` branch; schedule-tasks runs an autonomous branch+park model).
2. **Branch naming** (when branches are used): `feature/<short>`, `fix/<short>`,
   `chore/<short>`.
3. **Who commits.** Each sub-agent / teammate commits its OWN zone's changes when
   it finishes that zone. End every commit message with a footer line naming the
   zone: `Agent: <zone>` (e.g. `Agent: backend`). This `Agent: <zone>` marker is
   the ONLY allowed trailer — do NOT add `Co-Authored-By:`, `Generated with …`,
   or any other signature.
4. **Commit message format.** `<scope>: <imperative summary>`. Subject ≤72 chars,
   imperative mood. Body optional (may be in Russian) — include it only when it
   adds meaning not visible from the diff. Keep the whole message readable.
5. **Scopes** (generic default set): `api | db | infra | docs | task`. Projects
   extend/override this list in their own `CLAUDE.md` (e.g. a Go-client project
   may add `goclient`; a browser-extension project may add `ext`). Do NOT treat
   project-specific scopes as the canonical set.
6. **Staging — explicit paths only.** `git add <path> …`. Never `git add .`,
   `git add -A`, `git add -u`, or `git commit -a`. (Resume-context exception →
   schedule-tasks documents it.)
7. **Never force-push to the default branch. Never `git commit --no-verify`.**
8. **Moving / renaming / deleting tracked files** → use the
   [`git-move`](../git-move/SKILL.md) skill (`git mv` / `git rm`). Do not
   duplicate its mechanics.
9. **PR.** Title in English; body may be in Russian.

## How other skills relate to git-flow

| Skill | Follows CORE + its delta |
|---|---|
| [kanban](../kanban/SKILL.md) | Per-task `task/<ID>` branch; each sub-agent commits its zone; orchestrator finalizes; OK → squash-merge to default + rename branch to `done/<ID>` (strip the `task/` prefix — archive is `done/<ID>`, NOT `done/task/<ID>`). |
| [schedule-tasks](../schedule-tasks/SKILL.md) | Autonomous per-task `task/<NAME>` branch + park-commit model; finalization is the SAME as kanban (squash-merge to default, rename branch to `done/<NAME>`). Owns its autonomous park / commit-shape specifics. |
| [prepare-pr](../prepare-pr/SKILL.md) | PR assembly — sanity-check diff, run the gate, draft description. Draft-only by default. |
| [qa-check](../qa-check/SKILL.md) | Quality gate scoped by `git diff`; never auto-merge / auto-push. |
| [git-move](../git-move/SKILL.md) | Mechanics for `git mv` / `git rm` (rule 8). |

Each documents ONLY its context-specific deltas; everything else here is binding.
