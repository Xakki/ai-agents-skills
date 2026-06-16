---
name: prepare-pr
description: Prepare a branch for a pull request — sanity-check the diff, run the quality gate, and draft a PR description from the commits. Safe by default (draft-only, no auto-push, no auto-PR). Triggers — RU "подготовь PR", "собери PR", "оформи пулреквест"; EN "prepare a PR", "draft a pull request", "get this branch ready for review".
user-invocable: true
---

# prepare-pr

Gets the current branch ready for review. **Default mode is draft-only**: it
prepares the description and stops — it does **not** push or open a PR unless the
user asks. Stops on a red quality gate.

## Steps

1. **Sanity.** `git status` (clean? what's staged/untracked?) and
   `git log <base>..HEAD` + `git diff <base>..HEAD` to see what the PR contains.
2. **Quality gate — delegate to [`qa-check`](../qa-check/SKILL.md).** Do not
   re-implement the checks here. If qa-check is red → **stop**, report, fix root
   cause first.
3. **Secret / artifact leak guard.** Warn on suspicious untracked or staged files
   — never index them: `.env`, `*.pem`, `id_rsa`, `*.session`, `*credentials*`,
   `dump.sql`, `*.bak`. Add **specific files** (`git add <path>`), never
   `git add .` / `-A`.
4. **Draft the PR description** from the commits — sections: **Задача / Task**,
   **Что сделано / What changed**, **Что проверять / How to verify**, **Артефакты
   / Artifacts** (links, migrations, config). Keep it factual.
5. **Stop (draft mode).** Present the description + file list. Proceed to
   commit / push / open-PR **only on explicit user request** and per the mode
   chosen in ask-on-first-use.

## Commit message rule

Subject ≤ 72 chars, imperative, one line. **No trailers, no signatures** — never
add `Co-Authored-By`, `Generated with …`, or a `🤖` line. Body only if it adds
meaning not visible from the diff.

## Never

- `git add .` / `git add -A`; `git push --force` / `-f`; `git commit --no-verify`.
- Commit directly to the base branch (master/main) without an explicit request.
- Push or open a PR automatically because the gate passed.

## ask-on-first-use (per project)

Ask the user (don't guess) and offer to save to the project's `.claude/`:

1. **Base branch** (`master` / `main` / other).
2. **Mode** — `draft` (default), `commit`, `push`, or `create-PR`.
3. **PR title convention + body template** (any project-specific format).
4. *(optional)* **Secret deny-list** additions beyond the defaults above.
