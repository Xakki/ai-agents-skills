---
name: skill-import
description: Discover and import skills from external git repos into the current project's .claude/skills/, matched to the project's needs, with descriptions in the user's language, and keep them updatable. Триггеры RU — «импортируй скилы», «подбери скилы для проекта», «поставь скилы из репозитория», «обнови импортированные скилы», «какие скилы подойдут проекту»; EN — import skills, pick skills for this project, install skills from a repo, update imported skills, which skills fit this project.
---

# skill-import

Copies skills from configured source repos into `<project>/.claude/skills/`,
matched to what the project actually needs. Catalog is built on the fly into a
cache; imported skills are tracked for updates.

Set `ROOT="${AI_AGENTS_SKILLS_ROOT:-${CLAUDE_PLUGIN_ROOT:-${PLUGIN_ROOT:-${CURSOR_PLUGIN_ROOT:-}}}}"`. Scripts run via `"$ROOT"/skills/skill-import/<script>`:
`build-catalog.sh`, `import-skill.sh`, `update-imported.sh`. Config:
`sources.tsv` (append a row to add a repo). Details, catalog/manifest formats
and the matcher prompt: [reference.md](reference.md).

## Modes

| Mode | What it does |
|---|---|
| **discover** (default) | build catalog → delegate matching to a subagent → present options in the user's language → import chosen |
| **update** | `update-imported.sh [skill\|--all]` — re-sync imported skills |
| **list** | show `<project>/.claude/skills/.imported.tsv` |
| **add-source** | append a `name<TAB>url<TAB>type` row to `sources.tsv` |

## Discover (happy path)

1. Build/refresh the catalog:
   `bash "$ROOT"/skills/skill-import/build-catalog.sh`
   (writes `${SKILL_IMPORT_CACHE:-~/.cache/skill-import}/catalog.tsv`).
2. **Delegate matching to a subagent** — do NOT read the full catalog into the
   main thread. Hand the subagent the catalog path and the project's doc paths
   (`README*`, `CLAUDE.md`/`AGENTS.md`, stack manifests). It returns a ranked
   shortlist: `skill · source · kind · location · why_relevant` (English). See
   the matcher prompt in [reference.md](reference.md).
3. Present the shortlist to the user **in their language** (translate the
   description + why-relevant). Let them choose.
4. Import each chosen skill:
   `bash "$ROOT"/skills/skill-import/import-skill.sh <source> <skill>`
   (run from the project root, or pass `--project <dir>`).
5. The import **stages** files; commit via the `git-flow` skill.

## Safety

- Sources are read-only; scripts never push to them.
- Import never overwrites an existing project skill without `--force`.
- Update never overwrites a differing copy without `--force` (shows the diff).
- Copy stages only — commits are `git-flow`'s job.
