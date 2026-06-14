---
name: git-move
description: Move/rename or delete a file or directory while preserving git tracking. Uses `git mv` / `git rm` when the path is tracked, else plain `mv` / `rm`. Use this instead of bare mv/rm whenever relocating, renaming, or removing files/dirs that may be under git — e.g. moving kanban cards between stage dirs, renaming source files, deleting tracked docs.
---

# git-move — file ops that respect git

When moving, renaming, or deleting a file/directory that **might be tracked by
git**, never use bare `mv` / `rm` — that drops git's rename/delete tracking and
leaves the index inconsistent. Use the helper:

```bash
"${CLAUDE_PLUGIN_ROOT}"/skills/git-move/git-move.sh <src> <dst>        # move / rename
"${CLAUDE_PLUGIN_ROOT}"/skills/git-move/git-move.sh --rm <path> [path…] # delete
```

Behaviour:
- Tracked path inside a work tree → `git mv` / `git rm` (history + index stay clean).
- Untracked path, or not in a git repo → plain `mv` / `rm -rf` (fallback).
- Destination parent dirs are created automatically (`mkdir -p`).
- **Staging only — it never commits.** You commit separately when asked.

Examples:

```bash
"${CLAUDE_PLUGIN_ROOT}"/skills/git-move/git-move.sh .claude/kanban/grooming/foo.md .claude/kanban/todo/foo.md
"${CLAUDE_PLUGIN_ROOT}"/skills/git-move/git-move.sh --rm .claude/kanban/todo/old.md .claude/kanban/todo/dup.md
```
