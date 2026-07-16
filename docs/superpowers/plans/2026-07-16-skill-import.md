# skill-import Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a plugin skill `skill-import` that discovers skills in configured external git repos, matches them to a project's needs, copies chosen ones into the project's `.claude/skills/`, and updates them later.

**Architecture:** Three POSIX-bash scripts (`build-catalog.sh`, `import-skill.sh`, `update-imported.sh`) driven by a `sources.tsv` config, plus a `SKILL.md`/`reference.md` pair that tells the team-lead to delegate matching to a subagent. Catalog is generated on the fly into a local cache; imported skills are tracked by a per-project `.claude/skills/.imported.tsv` manifest.

**Tech Stack:** Bash (`set -euo pipefail`), `git`, `awk`/`sed`, `find`. Tests are plain bash scripts using local `git init` fixture repos cloned over `file://` (fully offline, no network).

## Global Constraints

- Scripts start with `set -euo pipefail` and expose a `usage()` heredoc; mirror `skills/git-move/git-move.sh` style.
- In-repo paths use `${CLAUDE_PLUGIN_ROOT}` in docs; scripts locate their own dir via `SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"` — never hardcode host/user paths.
- Cache dir: `${SKILL_IMPORT_CACHE:-$HOME/.cache/skill-import}`. Clone URLs are HTTPS. Never push to sources.
- Copy operations `git add` but NEVER commit (commits are `git-flow`'s job).
- No silent overwrite: existing project skills and locally-modified imported skills require `--force`.
- SKILL.md `description` is one line ending with bilingual triggers (RU «…» / EN …), matching the repo convention.
- All skill files (`SKILL.md`, `reference.md`, scripts) are written in English.
- Catalog TSV columns (exact order): `source  skill  kind  location  description`. Manifest TSV columns (exact order): `skill  source  url  location  commit_sha  date`.

---

### Task 1: Scaffold + `sources.tsv` + `build-catalog.sh` local enumeration

**Files:**
- Create: `skills/skill-import/sources.tsv`
- Create: `skills/skill-import/build-catalog.sh`
- Test: `skills/skill-import/test/build-catalog.test.sh`

**Interfaces:**
- Produces: `build-catalog.sh [--offline] [--cache DIR] [--sources FILE] [--out FILE]` → writes catalog TSV (header + rows) to `${cache}/catalog.tsv` (or `--out`). Row for a local skill: `<source>\t<skill>\tlocal\t<rel_path>\t<description>`.
- Produces: `sources.tsv` rows `name\tclone_url\ttype` (`type` ∈ `skills-repo`, `hybrid`).

- [ ] **Step 1: Write the failing test**

```bash
# skills/skill-import/test/build-catalog.test.sh
#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../build-catalog.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
git_c() { git -c user.email=t@t -c user.name=t -c init.defaultBranch=main "$@"; }

# fixture source repo with two skill dirs
SRC="$TMP/src"; mkdir -p "$SRC/react" "$SRC/docker/nested"
cat >"$SRC/react/SKILL.md" <<'EOF'
---
name: react
description: React best practices and hooks. Use for React apps.
---
# React
EOF
cat >"$SRC/docker/nested/SKILL.md" <<'EOF'
---
name: docker-nested
description: Docker guidance.
---
EOF
git_c init -q "$SRC"; git_c -C "$SRC" add -A; git_c -C "$SRC" commit -qm init

SOURCES="$TMP/sources.tsv"
printf 'mysrc\tfile://%s\tskills-repo\n' "$SRC" >"$SOURCES"
CACHE="$TMP/cache"; OUT="$TMP/catalog.tsv"

bash "$SCRIPT" --cache "$CACHE" --sources "$SOURCES" --out "$OUT"

grep -qP '^mysrc\treact\tlocal\treact\tReact best practices' "$OUT" || { echo "FAIL: react row"; cat "$OUT"; exit 1; }
grep -qP '^mysrc\tdocker-nested\tlocal\tdocker/nested\t' "$OUT" || { echo "FAIL: nested row"; cat "$OUT"; exit 1; }
echo "PASS build-catalog local"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash skills/skill-import/test/build-catalog.test.sh`
Expected: FAIL — `build-catalog.sh` does not exist.

- [ ] **Step 3: Create `sources.tsv`**

```tsv
# name	clone_url	type
mindrally	https://github.com/Mindrally/skills.git	skills-repo
composio	https://github.com/ComposioHQ/awesome-claude-skills.git	hybrid
```

- [ ] **Step 4: Write minimal `build-catalog.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() { cat <<EOF
Usage: build-catalog.sh [--offline] [--cache DIR] [--sources FILE] [--out FILE]
Clone/refresh source repos and generate a skills catalog TSV.
  --offline       do not fetch/clone; use existing cache only
  --cache DIR     cache dir (default: \${SKILL_IMPORT_CACHE:-\$HOME/.cache/skill-import})
  --sources FILE  sources.tsv (default: alongside this script)
  --out FILE      catalog output (default: <cache>/catalog.tsv)
Catalog columns: source  skill  kind  location  description
EOF
}

CACHE="${SKILL_IMPORT_CACHE:-$HOME/.cache/skill-import}"
SOURCES="$SCRIPT_DIR/sources.tsv"
OUT=""
OFFLINE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --offline) OFFLINE=1;;
    --cache) CACHE="$2"; shift;;
    --sources) SOURCES="$2"; shift;;
    --out) OUT="$2"; shift;;
    -h|--help) usage; exit 0;;
    *) echo "unknown arg: $1" >&2; usage >&2; exit 2;;
  esac
  shift
done
[ -n "$OUT" ] || OUT="$CACHE/catalog.tsv"
mkdir -p "$CACHE/repos" "$(dirname "$OUT")"

# extract a single-line frontmatter field from a SKILL.md
fm_field() { # file field
  awk -v f="$2" '
    BEGIN{fm=0}
    /^---[[:space:]]*$/ { fm++; if (fm>=2) exit; next }
    fm==1 && $0 ~ "^"f":" { sub("^"f":[[:space:]]*",""); gsub(/[[:space:]]+$/,""); print; exit }
  ' "$1"
}

refresh_repo() { # name url -> echoes clone dir
  local name="$1" url="$2" dir="$CACHE/repos/$1"
  if [ ! -d "$dir/.git" ]; then
    [ "$OFFLINE" = 1 ] && { echo "offline: missing cache for $name" >&2; return 1; }
    git clone --depth 1 -q "$url" "$dir"
  elif [ "$OFFLINE" != 1 ]; then
    git -C "$dir" fetch --depth 1 -q origin && git -C "$dir" reset --hard -q FETCH_HEAD
  fi
  printf '%s' "$dir"
}

emit_local() { # source clone_dir
  local source="$1" clone="$2" md dir rel skill desc
  while IFS= read -r md; do
    dir="${md%/SKILL.md}"; rel="${dir#"$clone"/}"
    skill="$(fm_field "$md" name)"; [ -n "$skill" ] || skill="$(basename "$dir")"
    desc="$(fm_field "$md" description)"
    printf '%s\t%s\tlocal\t%s\t%s\n' "$source" "$skill" "$rel" "$desc" >>"$OUT"
  done < <(find "$clone" -name SKILL.md -not -path '*/.git/*' | sort)
}

printf 'source\tskill\tkind\tlocation\tdescription\n' >"$OUT"
while IFS=$'\t' read -r name url type; do
  case "$name" in ''|\#*) continue;; esac
  clone="$(refresh_repo "$name" "$url")" || continue
  emit_local "$name" "$clone"
  # hybrid external parsing added in Task 2
done < "$SOURCES"
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bash skills/skill-import/test/build-catalog.test.sh`
Expected: `PASS build-catalog local`

- [ ] **Step 6: Commit**

```bash
git add skills/skill-import/sources.tsv skills/skill-import/build-catalog.sh skills/skill-import/test/build-catalog.test.sh
git commit -m "feat(skill-import): catalog builder for skills-repo sources"
```

---

### Task 2: Hybrid README external-link parsing in `build-catalog.sh`

**Files:**
- Modify: `skills/skill-import/build-catalog.sh` (add `emit_external`, call for `hybrid`)
- Test: `skills/skill-import/test/build-catalog-hybrid.test.sh`

**Interfaces:**
- Consumes: `refresh_repo`, `emit_local` from Task 1.
- Produces: for a `hybrid` source, additional rows `<source>\t<slug>\texternal\t<url>\t<description>` parsed from `README.md` markdown list links to `github.com`.

- [ ] **Step 1: Write the failing test**

```bash
# skills/skill-import/test/build-catalog-hybrid.test.sh
#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../build-catalog.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
git_c() { git -c user.email=t@t -c user.name=t -c init.defaultBranch=main "$@"; }

SRC="$TMP/src"; mkdir -p "$SRC/local-one"
cat >"$SRC/local-one/SKILL.md" <<'EOF'
---
name: local-one
description: A local skill.
---
EOF
cat >"$SRC/README.md" <<'EOF'
# Awesome
## Skills
- [AWS Skills](https://github.com/zxkane/aws-skills) — AWS helpers for Claude.
- [Playwright](https://github.com/lackeyjb/playwright-skill) - browser automation.
- [Not a skill](https://example.com/blog) — ignored, not github.
EOF
git_c init -q "$SRC"; git_c -C "$SRC" add -A; git_c -C "$SRC" commit -qm init

SOURCES="$TMP/sources.tsv"
printf 'aw\tfile://%s\thybrid\n' "$SRC" >"$SOURCES"
CACHE="$TMP/cache"; OUT="$TMP/catalog.tsv"
bash "$SCRIPT" --cache "$CACHE" --sources "$SOURCES" --out "$OUT"

grep -qP '^aw\tlocal-one\tlocal\t' "$OUT" || { echo "FAIL local in hybrid"; cat "$OUT"; exit 1; }
grep -qP '^aw\taws-skills\texternal\thttps://github.com/zxkane/aws-skills\tAWS helpers' "$OUT" || { echo "FAIL external aws"; cat "$OUT"; exit 1; }
grep -qP '^aw\tplaywright-skill\texternal\thttps://github.com/lackeyjb/playwright-skill\tbrowser automation' "$OUT" || { echo "FAIL external pw"; cat "$OUT"; exit 1; }
grep -q 'example.com' "$OUT" && { echo "FAIL: non-github link leaked"; exit 1; }
echo "PASS build-catalog hybrid"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash skills/skill-import/test/build-catalog-hybrid.test.sh`
Expected: FAIL — no `external` rows emitted.

- [ ] **Step 3: Add `emit_external` and wire it for `hybrid`**

Add this function after `emit_local` in `build-catalog.sh`:

```bash
emit_external() { # source clone_dir
  local source="$1" clone="$2" readme="$2/README.md"
  [ -f "$readme" ] || return 0
  # match list items: - [text](https://github.com/....) <sep> description
  grep -oE '^[[:space:]]*[-*][[:space:]]+\[[^]]+\]\(https://github\.com/[^)]+\)[^`]*' "$readme" | \
  while IFS= read -r line; do
    local url slug desc
    url="$(printf '%s' "$line" | sed -E 's/.*\((https:\/\/github\.com\/[^)]+)\).*/\1/')"
    slug="$(basename "${url%/}")"
    desc="$(printf '%s' "$line" | sed -E 's/.*\)[[:space:]]*[—-]?[[:space:]]*//' | sed -E 's/[[:space:]]+$//')"
    printf '%s\t%s\texternal\t%s\t%s\n' "$source" "$slug" "$url" "$desc" >>"$OUT"
  done
}
```

Change the source loop body to branch on `type`:

```bash
  clone="$(refresh_repo "$name" "$url")" || continue
  emit_local "$name" "$clone"
  [ "$type" = hybrid ] && emit_external "$name" "$clone"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash skills/skill-import/test/build-catalog-hybrid.test.sh`
Expected: `PASS build-catalog hybrid`

- [ ] **Step 5: Re-run Task 1 test (no regression)**

Run: `bash skills/skill-import/test/build-catalog.test.sh`
Expected: `PASS build-catalog local`

- [ ] **Step 6: Commit**

```bash
git add skills/skill-import/build-catalog.sh skills/skill-import/test/build-catalog-hybrid.test.sh
git commit -m "feat(skill-import): parse awesome-list external links (hybrid)"
```

---

### Task 3: `import-skill.sh` — local import + manifest + collision guard

**Files:**
- Create: `skills/skill-import/import-skill.sh`
- Test: `skills/skill-import/test/import-skill.test.sh`

**Interfaces:**
- Consumes: catalog TSV from Task 1/2 (`--catalog FILE`), cache repos from `build-catalog.sh`.
- Produces: `import-skill.sh <source> <skill> [--force] [--project DIR] [--cache DIR] [--catalog FILE]` → copies skill dir to `<project>/.claude/skills/<skill>/`, appends/replaces a row in `<project>/.claude/skills/.imported.tsv` (`skill\tsource\turl\tlocation\tcommit_sha\tdate`), `git add`s (never commits). Exits 3 on collision without `--force`.

- [ ] **Step 1: Write the failing test**

```bash
# skills/skill-import/test/import-skill.test.sh
#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$HERE/../build-catalog.sh"; IMPORT="$HERE/../import-skill.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
git_c() { git -c user.email=t@t -c user.name=t -c init.defaultBranch=main "$@"; }

SRC="$TMP/src"; mkdir -p "$SRC/react"
printf -- '---\nname: react\ndescription: React best practices.\n---\n# React\n' >"$SRC/react/SKILL.md"
git_c init -q "$SRC"; git_c -C "$SRC" add -A; git_c -C "$SRC" commit -qm init

SOURCES="$TMP/sources.tsv"; printf 'mysrc\tfile://%s\tskills-repo\n' "$SRC" >"$SOURCES"
CACHE="$TMP/cache"; CAT="$TMP/catalog.tsv"
bash "$BUILD" --cache "$CACHE" --sources "$SOURCES" --out "$CAT"

PROJ="$TMP/proj"; mkdir -p "$PROJ"; git_c init -q "$PROJ"
bash "$IMPORT" mysrc react --project "$PROJ" --cache "$CACHE" --catalog "$CAT"

[ -f "$PROJ/.claude/skills/react/SKILL.md" ] || { echo "FAIL: not copied"; exit 1; }
grep -qP '^react\tmysrc\tfile://.*\treact\t[0-9a-f]{7,}\t' "$PROJ/.claude/skills/.imported.tsv" || { echo "FAIL: manifest"; cat "$PROJ/.claude/skills/.imported.tsv"; exit 1; }
git -C "$PROJ" diff --cached --name-only | grep -q '.claude/skills/react/SKILL.md' || { echo "FAIL: not staged"; exit 1; }

# collision without --force exits 3
set +e; bash "$IMPORT" mysrc react --project "$PROJ" --cache "$CACHE" --catalog "$CAT" >/dev/null 2>&1; rc=$?; set -e
[ "$rc" = 3 ] || { echo "FAIL: expected exit 3 on collision, got $rc"; exit 1; }
echo "PASS import-skill local"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash skills/skill-import/test/import-skill.test.sh`
Expected: FAIL — `import-skill.sh` does not exist.

- [ ] **Step 3: Write `import-skill.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() { cat <<EOF
Usage: import-skill.sh <source> <skill> [--force] [--project DIR] [--cache DIR] [--catalog FILE]
Copy a catalog skill into <project>/.claude/skills/<skill>/ and record the manifest.
Exit 3 on name collision without --force.
EOF
}

CACHE="${SKILL_IMPORT_CACHE:-$HOME/.cache/skill-import}"
PROJECT="$PWD"; FORCE=0; CATALOG=""
SOURCE=""; SKILL=""
while [ $# -gt 0 ]; do
  case "$1" in
    --force) FORCE=1;;
    --project) PROJECT="$2"; shift;;
    --cache) CACHE="$2"; shift;;
    --catalog) CATALOG="$2"; shift;;
    -h|--help) usage; exit 0;;
    -*) echo "unknown arg: $1" >&2; usage >&2; exit 2;;
    *) if [ -z "$SOURCE" ]; then SOURCE="$1"; elif [ -z "$SKILL" ]; then SKILL="$1"; else echo "extra arg: $1" >&2; exit 2; fi;;
  esac
  shift
done
[ -n "$SOURCE" ] && [ -n "$SKILL" ] || { usage >&2; exit 2; }
[ -n "$CATALOG" ] || CATALOG="$CACHE/catalog.tsv"
[ -f "$CATALOG" ] || { echo "no catalog: $CATALOG (run build-catalog.sh)" >&2; exit 1; }

# find the catalog row (source + skill)
row="$(awk -F'\t' -v s="$SOURCE" -v k="$SKILL" '$1==s && $2==k {print; exit}' "$CATALOG")"
[ -n "$row" ] || { echo "not in catalog: $SOURCE/$SKILL" >&2; exit 1; }
IFS=$'\t' read -r c_source c_skill c_kind c_loc c_desc <<<"$row"

url="$(awk -F'\t' -v s="$SOURCE" '$1!~/^#/ && $1==s {print $2; exit}' "$SCRIPT_DIR/sources.tsv" 2>/dev/null || true)"

dest="$PROJECT/.claude/skills/$SKILL"
if [ -d "$dest" ] && [ "$FORCE" != 1 ]; then
  echo "exists: $dest (use --force to overwrite)" >&2; exit 3
fi

if [ "$c_kind" = local ]; then
  clone="$CACHE/repos/$SOURCE"; src="$clone/$c_loc"
  sha="$(git -C "$clone" rev-parse --short HEAD)"
  rec_url="file://$clone"; [ -n "$url" ] && rec_url="$url"
  rec_loc="$c_loc"
else
  echo "external import handled in Task 4" >&2; exit 1
fi

mkdir -p "$dest"; rm -rf "${dest:?}/"* 2>/dev/null || true
cp -R "$src/." "$dest/"

# manifest: replace existing row for this skill, then append
man="$PROJECT/.claude/skills/.imported.tsv"
mkdir -p "$(dirname "$man")"; touch "$man"
tmp="$(mktemp)"; awk -F'\t' -v k="$SKILL" '$1!=k' "$man" >"$tmp" && mv "$tmp" "$man"
printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$SKILL" "$SOURCE" "$rec_url" "$rec_loc" "$sha" "$(date -u +%F)" >>"$man"

if git -C "$PROJECT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C "$PROJECT" add ".claude/skills/$SKILL" ".claude/skills/.imported.tsv"
fi
echo "imported $SOURCE/$SKILL -> $dest (do not forget to commit via git-flow)"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash skills/skill-import/test/import-skill.test.sh`
Expected: `PASS import-skill local`

- [ ] **Step 5: Commit**

```bash
git add skills/skill-import/import-skill.sh skills/skill-import/test/import-skill.test.sh
git commit -m "feat(skill-import): import local skill + manifest + collision guard"
```

---

### Task 4: `import-skill.sh` — external import (clone external repo / subpath)

**Files:**
- Modify: `skills/skill-import/import-skill.sh` (implement the `external` branch)
- Test: `skills/skill-import/test/import-external.test.sh`

**Interfaces:**
- Consumes: catalog `external` rows from Task 2 (`location` = a `https://github.com/...` URL, possibly `.../tree/<branch>/<subpath>`).
- Produces: for `external`, clone the repo into `$CACHE/external/<slug>`, resolve the skill dir (subpath if the URL has `/tree/<branch>/<subpath>`, else the SKILL.md dir), copy, and record `url`=repo URL, `location`=subpath (or `.`).

- [ ] **Step 1: Write the failing test**

```bash
# skills/skill-import/test/import-external.test.sh
#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMPORT="$HERE/../import-skill.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
git_c() { git -c user.email=t@t -c user.name=t -c init.defaultBranch=main "$@"; }

# external repo with SKILL.md at root
EXT="$TMP/ext"; mkdir -p "$EXT"
printf -- '---\nname: aws-skills\ndescription: AWS helpers.\n---\n# AWS\n' >"$EXT/SKILL.md"
git_c init -q "$EXT"; git_c -C "$EXT" add -A; git_c -C "$EXT" commit -qm init

CACHE="$TMP/cache"; mkdir -p "$CACHE"
CAT="$TMP/catalog.tsv"
printf 'source\tskill\tkind\tlocation\tdescription\n' >"$CAT"
printf 'aw\taws-skills\texternal\tfile://%s\tAWS helpers.\n' "$EXT" >>"$CAT"

PROJ="$TMP/proj"; mkdir -p "$PROJ"; git_c init -q "$PROJ"
bash "$IMPORT" aw aws-skills --project "$PROJ" --cache "$CACHE" --catalog "$CAT"

[ -f "$PROJ/.claude/skills/aws-skills/SKILL.md" ] || { echo "FAIL: external not copied"; exit 1; }
grep -qP '^aws-skills\taw\tfile://.*\t\.\t[0-9a-f]{7,}\t' "$PROJ/.claude/skills/.imported.tsv" || { echo "FAIL: external manifest"; cat "$PROJ/.claude/skills/.imported.tsv"; exit 1; }
echo "PASS import-skill external"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash skills/skill-import/test/import-external.test.sh`
Expected: FAIL — external branch prints "handled in Task 4" and exits 1.

- [ ] **Step 3: Replace the `external` branch in `import-skill.sh`**

Replace the `else echo "external import handled in Task 4"...` block with:

```bash
else
  # location is a github URL, optionally .../tree/<branch>/<subpath>
  repo_url="$c_loc"; subpath="."
  if printf '%s' "$c_loc" | grep -q '/tree/'; then
    subpath="$(printf '%s' "$c_loc" | sed -E 's#.*/tree/[^/]+/(.*)$#\1#')"
    repo_url="$(printf '%s' "$c_loc" | sed -E 's#(/tree/.*)$##')"
  fi
  slug="$(basename "${repo_url%/}" .git)"
  clone="$CACHE/external/$slug"
  if [ ! -d "$clone/.git" ]; then git clone --depth 1 -q "$repo_url" "$clone"; fi
  src="$clone/$subpath"
  # if no SKILL.md at subpath, try to find one
  if [ ! -f "$src/SKILL.md" ]; then
    found="$(find "$clone" -name SKILL.md -not -path '*/.git/*' | head -n1)"
    [ -n "$found" ] || { echo "no SKILL.md in $repo_url" >&2; exit 1; }
    src="${found%/SKILL.md}"
  fi
  sha="$(git -C "$clone" rev-parse --short HEAD)"
  rec_url="$repo_url"; rec_loc="$subpath"
fi
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash skills/skill-import/test/import-external.test.sh`
Expected: `PASS import-skill external`

- [ ] **Step 5: Re-run Task 3 test (no regression)**

Run: `bash skills/skill-import/test/import-skill.test.sh`
Expected: `PASS import-skill local`

- [ ] **Step 6: Commit**

```bash
git add skills/skill-import/import-skill.sh skills/skill-import/test/import-external.test.sh
git commit -m "feat(skill-import): external skill import via repo clone/subpath"
```

---

### Task 5: `update-imported.sh` — re-sync with diff guard

**Files:**
- Create: `skills/skill-import/update-imported.sh`
- Test: `skills/skill-import/test/update-imported.test.sh`

**Interfaces:**
- Consumes: `<project>/.claude/skills/.imported.tsv`, `import-skill.sh`, catalog/cache.
- Produces: `update-imported.sh [skill|--all] [--project DIR] [--cache DIR] [--catalog FILE] [--force]` → for each targeted imported skill, refresh source, and if the project copy differs from the (refreshed) source, print a diff summary; without `--force` exits 4 and copies nothing; with `--force` re-imports and updates the manifest sha.

- [ ] **Step 1: Write the failing test**

```bash
# skills/skill-import/test/update-imported.test.sh
#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$HERE/../build-catalog.sh"; IMPORT="$HERE/../import-skill.sh"; UPDATE="$HERE/../update-imported.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
git_c() { git -c user.email=t@t -c user.name=t -c init.defaultBranch=main "$@"; }

SRC="$TMP/src"; mkdir -p "$SRC/react"
printf -- '---\nname: react\ndescription: v1.\n---\n# React v1\n' >"$SRC/react/SKILL.md"
git_c init -q "$SRC"; git_c -C "$SRC" add -A; git_c -C "$SRC" commit -qm v1

SOURCES="$TMP/sources.tsv"; printf 'mysrc\tfile://%s\tskills-repo\n' "$SRC" >"$SOURCES"
CACHE="$TMP/cache"; CAT="$TMP/catalog.tsv"
bash "$BUILD" --cache "$CACHE" --sources "$SOURCES" --out "$CAT"
PROJ="$TMP/proj"; mkdir -p "$PROJ"; git_c init -q "$PROJ"
bash "$IMPORT" mysrc react --project "$PROJ" --cache "$CACHE" --catalog "$CAT"
old_sha="$(awk -F'\t' '{print $5}' "$PROJ/.claude/skills/.imported.tsv")"

# advance the source
printf -- '---\nname: react\ndescription: v2.\n---\n# React v2\n' >"$SRC/react/SKILL.md"
git_c -C "$SRC" commit -qam v2

# without --force: exit 4, no change
set +e; bash "$UPDATE" react --project "$PROJ" --cache "$CACHE" --sources "$SOURCES" >/dev/null 2>&1; rc=$?; set -e
[ "$rc" = 4 ] || { echo "FAIL: expected exit 4 without force, got $rc"; exit 1; }
grep -q 'React v1' "$PROJ/.claude/skills/react/SKILL.md" || { echo "FAIL: changed without force"; exit 1; }

# with --force: updates content + sha
bash "$UPDATE" react --project "$PROJ" --cache "$CACHE" --sources "$SOURCES" --force
grep -q 'React v2' "$PROJ/.claude/skills/react/SKILL.md" || { echo "FAIL: not updated with force"; exit 1; }
new_sha="$(awk -F'\t' '{print $5}' "$PROJ/.claude/skills/.imported.tsv")"
[ "$new_sha" != "$old_sha" ] || { echo "FAIL: sha not bumped"; exit 1; }
echo "PASS update-imported"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash skills/skill-import/test/update-imported.test.sh`
Expected: FAIL — `update-imported.sh` does not exist.

- [ ] **Step 3: Write `update-imported.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$SCRIPT_DIR/build-catalog.sh"; IMPORT="$SCRIPT_DIR/import-skill.sh"

usage() { cat <<EOF
Usage: update-imported.sh [skill|--all] [--project DIR] [--cache DIR] [--catalog FILE] [--sources FILE] [--force]
Re-sync imported skills from their sources. Without --force, only reports diffs (exit 4 if any).
EOF
}

CACHE="${SKILL_IMPORT_CACHE:-$HOME/.cache/skill-import}"
PROJECT="$PWD"; CATALOG=""; SOURCES="$SCRIPT_DIR/sources.tsv"; FORCE=0; TARGET="--all"
while [ $# -gt 0 ]; do
  case "$1" in
    --all) TARGET="--all";;
    --force) FORCE=1;;
    --project) PROJECT="$2"; shift;;
    --cache) CACHE="$2"; shift;;
    --catalog) CATALOG="$2"; shift;;
    --sources) SOURCES="$2"; shift;;
    -h|--help) usage; exit 0;;
    -*) echo "unknown arg: $1" >&2; usage >&2; exit 2;;
    *) TARGET="$1";;
  esac
  shift
done
[ -n "$CATALOG" ] || CATALOG="$CACHE/catalog.tsv"
man="$PROJECT/.claude/skills/.imported.tsv"
[ -f "$man" ] || { echo "no manifest: $man" >&2; exit 1; }

# refresh sources + rebuild catalog so cache/catalog reflect latest
bash "$BUILD" --cache "$CACHE" --sources "$SOURCES" --out "$CATALOG" >/dev/null

changed=0
while IFS=$'\t' read -r skill source url location sha date; do
  case "$skill" in ''|\#*) continue;; esac
  [ "$TARGET" = "--all" ] || [ "$TARGET" = "$skill" ] || continue
  dest="$PROJECT/.claude/skills/$skill"
  # resolve current source dir from catalog
  row="$(awk -F'\t' -v s="$source" -v k="$skill" '$1==s && $2==k {print; exit}' "$CATALOG")"
  [ -n "$row" ] || { echo "warn: $source/$skill no longer in catalog" >&2; continue; }
  IFS=$'\t' read -r _ _ kind loc _ <<<"$row"
  if [ "$kind" = local ]; then srcdir="$CACHE/repos/$source/$loc"; else srcdir=""; fi
  if [ -n "$srcdir" ] && [ -d "$srcdir" ] && diff -rq "$srcdir" "$dest" >/dev/null 2>&1; then
    continue   # identical, nothing to do
  fi
  changed=1
  if [ "$FORCE" != 1 ]; then
    echo "DIFF $skill ($source): project copy differs from source"
    [ -n "$srcdir" ] && diff -rq "$srcdir" "$dest" 2>/dev/null || true
  else
    bash "$IMPORT" "$source" "$skill" --project "$PROJECT" --cache "$CACHE" --catalog "$CATALOG" --force
  fi
done < "$man"

if [ "$FORCE" != 1 ] && [ "$changed" = 1 ]; then
  echo "run with --force to apply updates" >&2; exit 4
fi
echo "update complete"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash skills/skill-import/test/update-imported.test.sh`
Expected: `PASS update-imported`

- [ ] **Step 5: Commit**

```bash
git add skills/skill-import/update-imported.sh skills/skill-import/test/update-imported.test.sh
git commit -m "feat(skill-import): update-imported re-sync with diff guard"
```

---

### Task 6: `SKILL.md` + `reference.md`

**Files:**
- Create: `skills/skill-import/SKILL.md`
- Create: `skills/skill-import/reference.md`
- Test: `skills/skill-import/test/docs.test.sh`

**Interfaces:**
- Consumes: all three scripts (referenced via `${CLAUDE_PLUGIN_ROOT}` in the body).
- Produces: the user-facing skill entry; `SKILL.md` frontmatter (`name: skill-import`, one-line `description` with RU/EN triggers), a modes table (discover/update/list/add-source), and a delegation instruction to run the matcher as a subagent.

- [ ] **Step 1: Write the failing test**

```bash
# skills/skill-import/test/docs.test.sh
#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SK="$HERE/../SKILL.md"; REF="$HERE/../reference.md"
[ -f "$SK" ] || { echo "FAIL: no SKILL.md"; exit 1; }
[ -f "$REF" ] || { echo "FAIL: no reference.md"; exit 1; }
head -1 "$SK" | grep -q '^---$' || { echo "FAIL: no frontmatter"; exit 1; }
grep -qP '^name:[[:space:]]*skill-import[[:space:]]*$' "$SK" || { echo "FAIL: name"; exit 1; }
grep -qi 'description:.*import' "$SK" || { echo "FAIL: description keyword"; exit 1; }
grep -q 'Триггеры' "$SK" || { echo "FAIL: RU triggers"; exit 1; }
grep -q 'build-catalog.sh' "$SK" || { echo "FAIL: no script ref"; exit 1; }
grep -qi 'subagent' "$SK" || { echo "FAIL: no delegation note"; exit 1; }
echo "PASS docs"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash skills/skill-import/test/docs.test.sh`
Expected: FAIL — no `SKILL.md`.

- [ ] **Step 3: Write `SKILL.md`**

```markdown
---
name: skill-import
description: Discover and import skills from external git repos into the current project's .claude/skills/, matched to the project's needs, with descriptions in the user's language, and keep them updatable. Триггеры RU — «импортируй скилы», «подбери скилы для проекта», «поставь скилы из репозитория», «обнови импортированные скилы», «какие скилы подойдут проекту»; EN — import skills, pick skills for this project, install skills from a repo, update imported skills, which skills fit this project.
---

# skill-import

Copies skills from configured source repos into `<project>/.claude/skills/`,
matched to what the project actually needs. Catalog is built on the fly into a
cache; imported skills are tracked for updates.

Scripts (run via `"${CLAUDE_PLUGIN_ROOT}"/skills/skill-import/<script>`):
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
   `bash "${CLAUDE_PLUGIN_ROOT}"/skills/skill-import/build-catalog.sh`
   (writes `${SKILL_IMPORT_CACHE:-~/.cache/skill-import}/catalog.tsv`).
2. **Delegate matching to a subagent** — do NOT read the full catalog into the
   main thread. Hand the subagent the catalog path and the project's doc paths
   (`README*`, `CLAUDE.md`/`AGENTS.md`, stack manifests). It returns a ranked
   shortlist: `skill · source · kind · location · why_relevant` (English). See
   the matcher prompt in [reference.md](reference.md).
3. Present the shortlist to the user **in their language** (translate the
   description + why-relevant). Let them choose.
4. Import each chosen skill:
   `bash "${CLAUDE_PLUGIN_ROOT}"/skills/skill-import/import-skill.sh <source> <skill>`
   (run from the project root, or pass `--project <dir>`).
5. The import **stages** files; commit via the `git-flow` skill.

## Safety

- Sources are read-only; scripts never push to them.
- Import never overwrites an existing project skill without `--force`.
- Update never overwrites a differing copy without `--force` (shows the diff).
- Copy stages only — commits are `git-flow`'s job.
```

- [ ] **Step 4: Write `reference.md`**

```markdown
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
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bash skills/skill-import/test/docs.test.sh`
Expected: `PASS docs`

- [ ] **Step 6: Commit**

```bash
git add skills/skill-import/SKILL.md skills/skill-import/reference.md skills/skill-import/test/docs.test.sh
git commit -m "docs(skill-import): SKILL.md + reference.md"
```

---

### Task 7: Register the skill (README + manifests) + full test sweep

**Files:**
- Modify: `README.md` (add a skill table row)
- Modify: `.claude-plugin/plugin.json` (mention in `description`)
- Modify: `.claude-plugin/marketplace.json` (mention in plugin `description`)
- Create: `skills/skill-import/test/run-all.sh`

**Interfaces:**
- Consumes: nothing new — final wiring + aggregate test runner.
- Produces: a discoverable, documented skill and a one-shot test runner.

- [ ] **Step 1: Write the aggregate test runner**

```bash
# skills/skill-import/test/run-all.sh
#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
rc=0
for t in "$HERE"/*.test.sh; do
  echo "== $(basename "$t") =="
  bash "$t" || rc=1
done
[ "$rc" = 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$rc"
```

- [ ] **Step 2: Add the README table row**

In `README.md`, add to the skills table (keep alphabetical/section order consistent with the file):

```markdown
| `skill-import` | Discover & import skills from external git repos into a project's `.claude/skills/`, matched to the project, with updates |
```

- [ ] **Step 3: Mention in `plugin.json` and `marketplace.json`**

Append `skill-import` to the free-text `description` string listing skills in both `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` (find the sentence that enumerates skills and add it there). Do not add any skills array — skills are auto-discovered.

- [ ] **Step 4: Run the full sweep**

Run: `bash skills/skill-import/test/run-all.sh`
Expected: `ALL PASS`

- [ ] **Step 5: Commit**

```bash
git add README.md .claude-plugin/plugin.json .claude-plugin/marketplace.json skills/skill-import/test/run-all.sh
git commit -m "feat(skill-import): register skill (README + manifests) + test runner"
```

---

## Self-Review

- **Spec coverage:** sources.tsv (T1) · on-the-fly catalog + cache (T1) · hybrid external links (T2) · matcher subagent + user-language presentation (T6 SKILL.md/reference) · local import + manifest + collision guard (T3) · external import (T4) · update with diff guard (T5) · registration + conventions (T7). All spec sections mapped.
- **Placeholders:** none — every code step has full content; the only forward reference ("handled in Task 4") is an intentional runtime error stub replaced in T4.
- **Type/name consistency:** catalog columns `source/skill/kind/location/description` and manifest columns `skill/source/url/location/commit_sha/date` are used identically across build/import/update. Script flags (`--cache/--project/--catalog/--sources/--force/--offline`) are consistent.
- **Note for reviewer:** external-link README parsing (T2) and shallow-clone diffing (T5 uses `diff -rq` rather than sha-range diff because `--depth 1` clones lack history) are the two heuristic areas most worth scrutiny.
