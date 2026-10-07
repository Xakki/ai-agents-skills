# Kanban lifecycle (autonomous run contract)

The autonomous prompt walks one approved card through `todo → progress → test → ready`
on a dedicated `task/<NAME>` branch. A valid per-chain scope manifest permits a
narrow merge-at-ready exception after green QA and independent review. The card
remains in `ready/` under that grant alone. The manifest authorizes only its exact
ordered card list, merge-at-ready and chaining within that list; by itself it
never grants `done`, push or deploy. `ready` is a required verified checkpoint,
not a compulsory human stop: proceed through `done`, merge, push, or deploy only
when valid action-specific authorization covers each target and mandatory
gates pass, without expanding the immutable card allowlist. Otherwise retain
the eligible state and report the missing grant.

## Branch model

| Phase | Branch | What happens |
|-------|--------|--------------|
| Start | **base** | `git mv todo→progress` + commit; then `git switch -c "task/<NAME>"` |
| Impl / qa / review | `task/<NAME>` | all work + commits |
| Finalize (ok, in scope) | `task/<NAME>` → **base** | `git mv test→ready` + commit; green QA + independent review; `git switch base`; `git merge --squash "task/<NAME>"` + `task: <NAME> merged (ready)` commit; card stays in `ready/`; archive branch as `done/<NAME>` |
| Additional finalization (if independently authorized) | `task/<NAME>` → **base** | verified ready checkpoint; authorized `ready→done` card move/commit; authorized squash merge after clean verification. Return safely to base before the scoped chain when merge is ungranted; retain the branch/card. Archive-rename only after a successful verified merge. |
| Park (any failure) | `task/<NAME>` | `wip(park): <NAME> (<REASON>)` via `park-task.sh`; branch stays; base stays clean |

## Commit shape per card

Happy path — 4+ commits on branch (except the start commit which lands on base):

| #  | Branch  | Commit subject                              | Content                                                                |
|----|---------|---------------------------------------------|------------------------------------------------------------------------|
| 1  | base    | `task: start <NAME> (todo→progress)`        | `git mv todo→progress` only                                            |
| 2+ | task/*  | `<scope>: <short description>` (one or more)| Code + Execution Log; scope: `api\|db\|infra\|docs\|task` (per git-flow)|
| 3  | task/*  | `task: review <NAME> (progress→test)`       | `git mv progress→test` only                                            |
| 4  | task/*  | `task: ready <NAME> (test→ready)`           | `git mv test→ready` only                                               |
| — scoped merge — | base | one squash commit `task: <NAME> merged (ready)` | lands all branch commits on base as ONE commit; card remains in `ready/`; branch renamed to `done/<NAME>` |
| 5  | task/*  | `task: done <NAME>` (if authorized)          | exact card transition and commit; parent-before-child EPIC gate applies |
| — merge — | base | one squash commit `task: <NAME> done`    | only after `done` and clean verification, and when merge is authorized; verify base/card result, then archive as `done/<NAME>` |

Park-path commit (on `task/<NAME>` branch only — via `park-task.sh`):

| Reason         | Commit subject                                  |
|----------------|-------------------------------------------------|
| qa-fail        | `wip(park): <NAME> (qa-fail)`                   |
| review-fail    | `wip(park): <NAME> (review-fail)`               |
| blocker        | `wip(park): <NAME> (blocker)`                   |
| question       | `wip(park): <NAME> (question)`                  |
| merge-conflict | `wip(park): <NAME> (merge-conflict)`            |

The branch archive name `done/<NAME>` means merged branch only; it does not
change the card's Kanban stage. The scope manifest alone leaves the card ready.
The chain may write `done/` only when valid action-specific authorization
covers the card; otherwise `ready→done` remains pending. A card stage alone
does not authorize merge, push, or deploy. If merge is not authorized, do not
archive the unmerged branch: after verifying the owned commit and preserving
pre-existing dirty work, safely return to base before step 9. Keep the task
branch and report that the card remains there and the canonical base has not
received it. If switching would overwrite or disturb dirty work, stop without
running the next-task chain. After an actual authorized push/deploy, read back
the exact target and verify the expected remote revision/deployed version or
state before claiming success.

The `progress/`, `test/`, and `ready/` directories may not exist in fresh repos — the
agent runs `mkdir -p .claude/kanban/{progress,test,ready}` once before the first
transition that needs them.

## Outcome mapping (where the card lands → result code)

All three outcomes **advance the chain** (step 9 always runs). There is no terminal `fail` —
every failure becomes a `park`.

| Final location | `AUTO-RUN-RESULT` | Chain    | Cause                                                              |
|----------------|-------------------|----------|--------------------------------------------------------------------|
| `ready/` (merged to base; card still ready) | `ok` | **advances within scope** | Implementation green, review green, approved merge to base |
| `done/` (verified merge to base) | `ok` | **advances** | Implementation/review green, authorized merge verified |
| `ready/` or `done/` on task branch (merge not authorized) | `ok` | **advances after safe return to base** | Card remains on task branch; canonical base is not merged; retain branch |
| `progress/` or `test/` + branch `task/<NAME>` | `park` | **advances** | Task parked: qa-fail, review-fail, blocker, question, or merge-conflict |
| `todo/`        | `skip`            | **advances** | Step-2 sanity: card not in `todo/` (already moved or wrong stage) |
| `grooming/`    | `skip`            | **advances** | Card was parked for clarification — chain skips and moves on      |

The current inner script reads `AUTO-RUN-RESULT:` from the session JSONL. If the
marker is missing or garbled, it sets the result to `unknown`, cancels any queued
continuation for that scope, and stops. Kanban-stage fallback is not implemented.

## Implementation step (project-agnostic)

The agent reads the card and implements it. For subagent / test-command
selection it inspects the **host project's** `CLAUDE.md`:

- If the project documents named subagents (e.g. under a "Сабагенты" / "Subagents" / "Specialised agents" section), the agent picks the one whose description matches the touched module. If none match, it implements directly. Before merge-at-ready, a separate fresh read-only reviewer must approve the diff; self-review or an unavailable reviewer is not approval and requires parking.
- For QA the agent runs the project's standard lint/test (commonly `make test` + `make lint`, otherwise whatever `CLAUDE.md` documents). If the project has no such command, the agent runs targeted tests for the touched files (e.g. `pytest <path>`, `npm test -- <pattern>`, `go test ./<pkg>`).
- The Execution Log section in the card is updated during implementation — those edits land in commit 1 alongside the code changes.

No project-specific agent names or skill names are hard-coded in the prompt.

## Next-task selection (for self-chain step)

Step 9 runs on **every** outcome (ok/park/skip) via `chain-next-task.sh`, which passes
the same SHA-256 scope ID to `select-next-task.sh`. The selector considers only exact
card basenames in the approved manifest that currently exist in `.claude/kanban/todo/`
(NOT `grooming/`), and it preserves manifest order:

1. **Move forward only.** After a run finishes, selection starts strictly after
   that card in the manifest and never wraps around. A card skipped earlier
   because it was blocked or absent is not reconsidered if its state later changes.
2. **Skip blocked cards.** A card is **blocked** if it contains a `depends on` /
   `blocked by` / `зависит от` / `блокируется` line (case-insensitive) referencing
   a task ID that currently has an entry in `.parked/`. Blocked cards are skipped;
   the chain picks the next unblocked candidate.
3. **Manifest order.** Preserve the exact recorded order; do not reorder the list
   using task relationships or lexical sorting, and never add a card absent from it.
4. **No eligible later card remains** → `AUTO-RUN-NEXT: none`,
   do NOT call `at`.

The selection logic lives in `scripts/select-next-task.sh` (args:
`<REPO> <PARKED_DIR> <JUST_FINISHED_NAME> <SCOPE_ID>`). Missing, malformed,
tampered, wrong-repository, or wrong-base manifests fail closed. To keep a card
out of the chain, do not include it in the approved list.

## Chain stops cleanly when

- No eligible next in-scope card (`AUTO-RUN-NEXT: none`) → chain ends. The
  scope manifest is retained as an audit record.
- Working tree (base) has **new** uncommitted paths at chain step (baseline-aware `comm -23`
  check — pre-existing dirt is fine). After a verified merge or a safe return from
  an unmerged ready/done task branch, this should not apply; after park (base
  stays clean) or skip (no branch created) it also should not apply.
- `atd` is inactive (`systemctl is-active atd` ≠ `active`).
- All remaining approved `todo/` cards are blocked (each depends-on a currently-parked task).
- Scope validation fails, the base branch changed, or a continuation is outside the manifest.

A stopped chain is **never** auto-restarted — the user re-arms via
`/schedule-tasks`.

## Proceed on dirty; preserve uncommitted; never bulk-stage

A dirty working tree is **not a reason to stop**. Step 1 of the autonomous prompt
tells the agent: tree may be dirty — proceed normally.

Rules:
- **No stash, no reset, no clean.** Pre-existing uncommitted files must never be touched
  except when the task itself needs to edit them.
- **Explicit-path staging only.** Every `git add` and `git commit` must name
  exact paths (`git add <paths>` / `git commit -- <paths>` or plain `git commit`
  after a `git mv`). NEVER `git add -A`, `git add .`, `git add -u`, `git commit -a`.
- **End-of-run auto-commit** (usage stats append) uses the baseline snapshot
  (`$LOG_DIR/.baseline-dirty-<TS>`) to distinguish pre-existing dirt from new
  task changes; it stages only those new kanban `.md` paths explicitly.
- **Chain dirty-check** (step 9) compares the current dirty set against the
  baseline snapshot with `comm -23`; pre-existing dirt is ignored, only new
  uncommitted task changes stop the chain.

One exception: a `wip(park): <NAME> (<REASON>)` commit IS made
during escalation — but only on the isolated `task/<NAME>` branch (explicit-path
staging applies there too), never on base.

## Guardrails in the prompt

- `git add -A`, `git add .`, `git add -u`, `git commit -a` — always stage explicit paths only
- `git stash`, `git checkout -- .`, `git reset --hard`, `git clean`
- Bundling `task: start <NAME> (todo→progress)` with implementation — the
  start mv is always its OWN commit before any code changes (required)
- Moving a card into `done/` without action-specific authorization; preserve the ready checkpoint and parent-before-child gate
- Starting a card from `grooming/` (chain only consumes `todo/`)
- Mixing content edits with `git mv` commits (commits 1, 3, 4 on happy path
  contain ONLY the kanban move — no Execution Log edits, no code changes).
- `--no-verify`
- `git push`, `gh pr create`, branch merges, or deploy without matching action-specific authorization and sanctioned workflow
- `AskUserQuestion` — the autonomous flow never blocks on a question; escalation parks instead
- WIP commits on the base branch — the `wip(park): ...` commit is the sole exception, and it
  is ONLY allowed on a `task/*` branch (never on base)
