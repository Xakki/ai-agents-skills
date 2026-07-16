# skill-import — design

Date: 2026-07-16
Status: approved (design), pending implementation plan

## Purpose

A plugin skill that, when run inside a target project, studies that project's
documentation, matches it against skills published in external git repos,
presents the fitting candidates **in the user's language** with descriptions,
copies the chosen ones into the project's `.claude/skills/`, and can later
update the imported copies from their sources.

Source repos are configured and **extensible** — new repos are added by
appending a row to a config file. Initial sources:

- `https://github.com/Mindrally/skills.git` — pure skills repo, 240+ skill dirs.
- `https://github.com/ComposioHQ/awesome-claude-skills.git` — hybrid: ~30 local
  skill dirs + an awesome-list README linking 100+ skills in external repos.

## Key decisions (agreed)

1. **Catalog is built on the fly** at run time into a local cache — not
   committed to the plugin. First run clones sources; later runs `git fetch` +
   reset (no re-clone of 240+ skills). Catalog is written to a file the matcher
   subagent reads.
2. **External awesome-list links are covered.** They appear in the catalog
   tagged `external`; copying one clones its own repo and extracts the subpath
   on demand.
3. **Imported skills are tracked by a per-project manifest**
   `.claude/skills/.imported.tsv` (skill, source, url, rel_path, commit_sha,
   date). Update = re-sync against the recorded source commit.
4. **HTTPS clone URLs** (repos are public) — no ssh key required.
5. Matcher runs as a **subagent** (team-lead delegates) so the large catalog and
   project docs stay out of the main thread's context. Subagent reasons in
   English; team-lead presents options to the user in Russian.
6. Copy operations **stage only, never commit** (defer commits to `git-flow`),
   mirroring the `git-move` skill.

## Components

### Files in the skill dir (`skills/skill-import/`)

```
SKILL.md            # essence, happy-path, modes, RU/EN triggers, safety
reference.md        # catalog format, matcher subagent prompt template,
                    # external-link handling, edge cases
sources.tsv         # configured source repos (extensible)
build-catalog.sh    # clone/pull sources into cache + generate catalog.tsv
import-skill.sh     # copy one skill into the project + record the manifest
update-imported.sh  # re-sync already-imported skills from their sources
```

### 1. Sources config — `sources.tsv`

Tab-separated, one row per source repo (`#` comments allowed):

```
name        clone_url                                              type
mindrally   https://github.com/Mindrally/skills.git                skills-repo
composio    https://github.com/ComposioHQ/awesome-claude-skills.git hybrid
```

- `type=skills-repo` — enumerate every dir containing `SKILL.md`.
- `type=hybrid` — enumerate local `SKILL.md` dirs AND parse the README's
  markdown links to external skills.

Adding a repo later = append a row.

### 2. Catalog builder — `build-catalog.sh`

- Cache dir `${SKILL_IMPORT_CACHE:-$HOME/.cache/skill-import}`.
- Per source: `git clone` if absent, else `git fetch origin && git reset --hard
  origin/HEAD`. Never pushes to sources. `--offline` flag skips network and uses
  the existing cache.
- Enumerate local skills: `find <clone> -name SKILL.md`; extract `name` and
  `description` from YAML frontmatter (collapse `description` to one line).
- For `hybrid`: also parse README markdown links under skill sections → rows
  tagged `external` with the external URL.
- Output `${CACHE}/catalog.tsv`, columns:
  `source ⇥ skill ⇥ kind(local|external) ⇥ location(rel_path|URL) ⇥ description`.

### 3. Matcher — subagent

The SKILL.md instructs the team-lead to delegate matching (not read the catalog
into the main thread):

- Inputs handed to the subagent: path to `catalog.tsv`; the target project's doc
  paths (`README*`, `CLAUDE.md`/`AGENTS.md`, and stack manifests such as
  `package.json`/`composer.json`/`go.mod`/`pyproject.toml` for stack detection).
- Task: read project docs, infer stack + needs, scan catalog descriptions,
  return a ranked shortlist — each entry: `skill`, `source`, `kind`,
  `location`, `why_relevant` (one line). English.
- Returns structured result to the team-lead.

The team-lead then presents the shortlist to the user **in Russian** (translated
description + why-relevant) and lets them select which to import
(AskUserQuestion / checklist).

### 4. Copier — `import-skill.sh <source> <skill>`

- Locate the skill dir in the cache (for `local`) or clone the external repo and
  extract the subpath (for `external`).
- Copy the whole skill dir → `<project>/.claude/skills/<skill>/`.
- **Collision guard:** if the target skill dir already exists, refuse and require
  an explicit `--force` / confirmation; never silently overwrite.
- Append/update `.claude/skills/.imported.tsv`:
  `skill ⇥ source ⇥ url ⇥ rel_path ⇥ commit_sha ⇥ date`.
- `git add` the new files; do **not** commit.

### 5. Updater — `update-imported.sh [skill|--all]`

- Read `.imported.tsv`; refresh the relevant source cache.
- Compare recorded `commit_sha` vs current source; if the skill's files changed,
  print a diff summary; on confirmation, re-copy and update the recorded sha.
- **Never silently overwrite** a locally-modified imported skill — detect local
  edits and require confirmation.

## Skill modes (SKILL.md)

- **discover** (default): build catalog → matcher subagent → present options →
  import chosen.
- **update**: run `update-imported.sh`.
- **list**: show `.imported.tsv`.
- **add-source**: how to append a row to `sources.tsv`.

## Conventions to follow

- In-repo paths via `${CLAUDE_PLUGIN_ROOT}`; never hardcode host/user paths.
- Scripts: `set -euo pipefail`, a `usage()` heredoc, small predicate helpers
  (mirror `git-move.sh`).
- SKILL.md lean; detail in `reference.md`.
- Register: add a README table row; mention in the two manifest `description`
  strings for discoverability (skills auto-discovered from `skills/`).
- SKILL.md `description` ends with bilingual triggers —
  RU «импортируй скилы», «подбери скилы для проекта», «обнови импортированные
  скилы»; EN import skills, pick skills for this project, update imported skills.

## Safety summary

- Sources are read-only; never push to them.
- Copy stages only, never commits (git-flow owns commits).
- Name-collision guard; no silent overwrite of existing project skills.
- Updater never clobbers locally-modified imported skills without confirmation.
