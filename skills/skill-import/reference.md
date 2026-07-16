# skill-import — reference

Source files: `build-catalog.sh`, `import-skill.sh`, `update-imported.sh`,
`sources.tsv`. Before relying on a fact here, verify it against those scripts;
on drift, fix this file in the same change and report to the team-lead.

## sources.tsv

Tab-separated `name<TAB>clone_url<TAB>type`; `#` comments allowed.
- `skills-repo` — every dir containing `SKILL.md` is a skill.
- `hybrid` — local `SKILL.md` dirs plus `github.com` links parsed from `README.md`.
Add a repo = append a row. Use HTTPS URLs (public repos, no ssh key needed).

## Catalog format (`<cache>/catalog.tsv`)

Header + rows `source<TAB>skill<TAB>kind<TAB>location<TAB>description`.
- `kind=local` → `location` is the skill dir path inside the source clone.
- `kind=external` → `location` is a `github.com` URL (may be `.../tree/<branch>/<subpath>`).
Built on the fly: first run clones (`--depth 1`), later runs fetch+reset. Use
`--offline` to reuse the cache without network.

## Matcher subagent prompt (template)

> You are picking skills for a project. Read `<catalog.tsv>` (columns:
> source, skill, kind, location, description) and the project docs at
> `<paths>`. Infer the project's stack and needs. Return a ranked shortlist
> (max ~12) of the most relevant skills, each as:
> `skill | source | kind | location | one-line why it fits this project`.
> Do not ask the user anything; return the list to the team-lead. English only.

The team-lead translates the shortlist into the user's language before showing it.

## Manifest (`<project>/.claude/skills/.imported.tsv`)

Rows `skill<TAB>source<TAB>url<TAB>location<TAB>commit_sha<TAB>date`. Written by
`import-skill.sh`; read by `update-imported.sh`.

## Frontmatter extraction caveat

`build-catalog.sh` reads only single-line `name:`/`description:` from
frontmatter. Multi-line/folded descriptions are truncated to the first line —
acceptable for catalog display.

## Edge cases

- External URL without a discoverable `SKILL.md` → import aborts.
- Collision: import exits 3; update exits 4 when a differing copy needs `--force`.
- `update-imported.sh` refreshes the catalog first, so a source removed upstream
  is reported as "no longer in catalog".

### Limitations — update behavior differs by kind

- **External-kind skills cannot be diffed locally.** Without `--force`,
  `update-imported.sh` does not flag them as changed — it prints
  `external <skill> (<source>): re-pull only with --force (cannot diff locally)`
  and skips them (no diff, no exit-4 trigger). Run
  `update-imported.sh <skill> --force` (or `--all --force`) to re-pull: this
  re-clones/fetches the latest into the external cache
  (`<cache>/external/<slug>`) and re-copies into the project.
- **Local-kind skills get a real content diff** (`diff -rq` between the
  refreshed source cache `<cache>/repos/<source>/<location>` and the project
  copy) and honor the normal no-force report / `--force` apply flow.
