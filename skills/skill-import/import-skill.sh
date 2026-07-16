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
    found="$(find "$clone" -name SKILL.md -not -path '*/.git/*' | head -n1 || true)"
    [ -n "$found" ] || { echo "no SKILL.md in $repo_url" >&2; exit 1; }
    src="${found%/SKILL.md}"
  fi
  sha="$(git -C "$clone" rev-parse --short HEAD)"
  rec_url="$repo_url"; rec_loc="$subpath"
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
