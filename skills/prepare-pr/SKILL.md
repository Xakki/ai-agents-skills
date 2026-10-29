---
name: prepare-pr
description: Prepare a pull request by reviewing the branch, running relevant checks and drafting a factual description; подготовь PR, оформи пулреквест.
---

# Prepare a pull request

Determine the actual base branch and requested scope from the task or repository; ask only if they cannot be established. Inspect the working tree, staged changes, branch history and complete diff against that base. Preserve unrelated staged and unstaged work, and review the proposed change for accidental credentials or generated artifacts without adding them to the index.

Run the relevant project-supported quality checks; use [qa-check](../qa-check/SKILL.md) when its workflow fits and is available. Report failures, skipped checks and limitations. Draft a title and description that explain the problem, resulting behavior and useful validation evidence. Follow the project's actual template when one exists.

Preparing a draft does not itself authorize committing, pushing or creating a pull request. Perform those actions when the current request or other valid authorization covers them, following the [Git workflow](../git-flow/SKILL.md) and the repository's branch and review policy. Do not assume a specific branch, trailer, agent configuration file or PR template.
