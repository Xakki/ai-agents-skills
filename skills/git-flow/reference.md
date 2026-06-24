# git-flow — reference

Rare/edge detail and longer examples behind the [SKILL.md](SKILL.md) CORE.

## Commit message examples

```
api: add pagination to /orders

Cursor-based; offset paging blew up past 100k rows on prod.

Agent: backend
```

```
docs: document the deploy rollback steps

Agent: docs
```

Minimal (no body, single-zone):

```
infra: pin redis image to 7.2

Agent: infra
```

## The `Agent: <zone>` footer

- One footer line, last line of the message.
- `<zone>` = the area the sub-agent owned (e.g. `backend`, `frontend`, `infra`,
  `db`, `docs`, `tests`). Keep it short and stable across a project.
- This is an explicit, scoped override of the global "no signatures/trailers"
  rule — it is the **only** trailer allowed. Still no `Co-Authored-By:`,
  `Generated with …`, emoji lines, etc.
- A solo agent working the whole change still adds the footer with the dominant
  zone (or `task` for pure board/stage work).

## Branches

- Default branch is whatever the project uses (`main` / `master` / other) — never
  assume; detect with `git rev-parse --abbrev-ref HEAD` / `git remote show`.
- User-requested branches: `feature/<short>`, `fix/<short>`, `chore/<short>`.
  `<short>` is a kebab-case slug, not a sentence.
- Skill-defined branches (`task/<ID>`, etc.) are owned by that skill — follow the
  skill, not these defaults.

## Staging — why explicit-path only

Bulk staging (`git add .` / `-A` / `-u`, `git commit -a`) sweeps in unrelated
working-tree changes (pre-existing dirt, other agents' WIP, secrets, build
artifacts). Always `git add` the specific paths the commit is about. The only
sanctioned exception is schedule-tasks' user-initiated **resume** path, which
guards with an active-run check before a one-shot bulk commit — see
[schedule-tasks](../schedule-tasks/SKILL.md).

## Force-push & no-verify

- No force-push (`--force` / `-f` / `--force-with-lease`) to the default branch.
  On a private feature branch a `--force-with-lease` after an interactive rebase
  is acceptable only when the user asked.
- Never `--no-verify` — pre-commit / pre-push hooks exist for a reason; fix the
  root cause instead of bypassing.
