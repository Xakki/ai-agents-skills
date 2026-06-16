---
name: qa-check
description: Run before marking any task complete to verify quality. Runs the project's lint/type/test/static-analysis checks via make, scoped to what changed. Triggers — RU "проверь качество", "прогони qa", "qa перед завершением"; EN "run qa", "quality check", "verify before done".
user-invocable: true
---

# qa-check

A quality gate you run **before** declaring a task done. It is project-agnostic:
it discovers *what* changed, maps that to the project's make targets, runs only
the relevant ones, and reports Pass/Fail per check.

## How to run

1. **Scope by the diff.** `git diff --name-only` (vs the base/last commit) →
   decide which check sections apply (backend / frontend / infra / docs). Run
   **only** the sections touching changed paths. Everything goes **through `make`**.
2. **Run the project's checks** for that scope (lint → type/static analysis →
   unit → targeted functional/e2e). See **ask-on-first-use** for the mapping.
3. **Report Pass/Fail per item.** Green = the command exits `0` **and** introduces
   no new warnings. Red = stop and fix the **root cause**, then re-run.

## Anti-patterns — never do these to make it "pass"

- Do NOT skip or disable lint / type checks.
- Do NOT mark tests skipped (`@pytest.mark.skip`, `.skip`, `xfail`, commenting
  out) without a real, stated reason.
- Do NOT use `--no-verify`, and never silence failures with `|| true` or by
  discarding stderr.
- Do NOT run the whole suite (`make test`) unless the user asks — use the
  targeted form (`name=<...>`) for the modules you touched.
- Do NOT auto-merge or auto-push because checks went green.

## ask-on-first-use (per project)

On the first run in a project you don't know its commands. **Ask the user** (don't
guess) and offer to save the answers to the project's `.claude/` (a line in
`<project>/CLAUDE.md` or a config file) so later runs skip the questions:

1. **Path/module → make targets** mapping (which lint + test targets cover which
   areas, e.g. backend vs frontend).
2. **The minimal always-run command** (e.g. `make lint`).
3. *(optional)* **Coverage gate** — threshold and where it's enforced.
