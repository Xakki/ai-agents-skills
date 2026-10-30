#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() { cat <<EOF
Usage: build-catalog.sh [--offline|--refresh] [--cache DIR] [--sources FILE] [--out FILE]
Generate a skills catalog TSV from existing caches; network requires --refresh.
  --offline       use existing caches only (default)
  --refresh       clone missing repos or fast-forward clean existing caches
  --cache DIR     cache dir (default: \${SKILL_IMPORT_CACHE:-\$HOME/.cache/skill-import})
  --sources FILE  sources.tsv (default: alongside this script)
  --out FILE      catalog output (default: <cache>/catalog.tsv)
Catalog columns: source  skill  kind  location  description
EOF
}

CACHE="${SKILL_IMPORT_CACHE:-$HOME/.cache/skill-import}"
SOURCES="$SCRIPT_DIR/sources.tsv"
OUT=""
OFFLINE=1
while [ $# -gt 0 ]; do
  case "$1" in
    --offline) OFFLINE=1;;
    --refresh) OFFLINE=0;;
    --cache) CACHE="$2"; shift;;
    --sources) SOURCES="$2"; shift;;
    --out) OUT="$2"; shift;;
    -h|--help) usage; exit 0;;
    *) echo "unknown arg: $1" >&2; usage >&2; exit 2;;
  esac
  shift
done
[ -n "$OUT" ] || OUT="$CACHE/catalog.tsv"
python3 - "$CACHE" <<'PY'
from pathlib import Path
import sys
cache=Path(sys.argv[1]).absolute()
for part in (cache, *cache.parents):
    if part.is_symlink(): raise SystemExit('skill-import: cache path contains a symlink')
if (cache/'repos').is_symlink(): raise SystemExit('skill-import: cache repositories path is a symlink')
PY
mkdir -p "$CACHE/repos" "$(dirname "$OUT")"
[ ! -L "$OUT" ] || { echo 'skill-import: catalog output must not be a symlink' >&2; exit 1; }
FINAL_OUT="$OUT"
OUT="$(mktemp "$(dirname "$FINAL_OUT")/.catalog.XXXXXXXX")"
trap 'rm -f -- "$OUT"' EXIT

# extract a single-line frontmatter field from a SKILL.md
fm_field() { # file field
  awk -v f="$2" '
    BEGIN{fm=0}
    /^---[[:space:]]*$/ { fm++; if (fm>=2) exit; next }
    fm==1 && $0 ~ "^"f":" {
      sub("^"f":[[:space:]]*","")
      gsub(/[[:space:]]+$/,"")
      val=$0
      # strip one matched pair of surrounding quotes
      if (val ~ /^".*"$/ || val ~ /^'"'"'.*'"'"'$/) val = substr(val, 2, length(val)-2)
      print val
      exit
    }
  ' "$1"
}

refresh_repo() { # name url -> echoes clone dir
  local name="$1" url="$2" dir="$CACHE/repos/$1"
  [[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ && "$name" != *..* ]] || { echo "skill-import: invalid source name" >&2; return 1; }
  [[ "$url" = https://* || "$url" = file://* ]] || { echo "skill-import: unsupported source URL" >&2; return 1; }
  [ ! -L "$dir" ] && [ ! -L "$dir/.git" ] || { echo 'skill-import: symlinked cache refused' >&2; return 1; }
  if [ ! -d "$dir/.git" ]; then
    [ "$OFFLINE" = 1 ] && { echo "offline: missing cache for $name" >&2; return 1; }
    [ ! -e "$dir" ] || { echo 'skill-import: cache destination already exists' >&2; return 1; }
    git clone --depth 1 -q -- "$url" "$dir" || return 1
  else
    local origin status branch
    origin="$(git -C "$dir" config --get-all remote.origin.url 2>/dev/null || true)"
    [ "$origin" = "$url" ] || { echo 'skill-import: cache origin mismatch' >&2; return 1; }
    if [ "$OFFLINE" != 1 ]; then
      status="$(git -C "$dir" status --porcelain --untracked-files=all)" || return 1
      [ -z "$status" ] || { echo 'skill-import: dirty source cache; refresh refused' >&2; return 1; }
      branch="$(git -C "$dir" symbolic-ref --quiet --short HEAD)" || { echo 'skill-import: detached cache cannot be refreshed' >&2; return 1; }
      git check-ref-format --branch "$branch" >/dev/null || return 1
      if [ "$(git -C "$dir" rev-parse --is-shallow-repository)" = true ]; then
        git -C "$dir" fetch --unshallow -q origin "refs/heads/$branch" || return 1
      else
        git -C "$dir" fetch -q origin "refs/heads/$branch" || return 1
      fi
      git -C "$dir" merge --ff-only -q FETCH_HEAD || return 1
    fi
  fi
  printf '%s' "$dir"
}

emit_local() { # source clone_dir
  local source="$1" clone="$2" md dir rel skill desc
  while IFS= read -r -d '' md; do
    dir="${md%/SKILL.md}"
    if [ "$dir" = "$clone" ]; then rel="."; else rel="${dir#"$clone"/}"; fi
    [[ "$rel" =~ ^[A-Za-z0-9._/-]+$ && "$rel" != *..* ]] || { echo 'skill-import: skipping unsupported source path' >&2; continue; }
    skill="$(fm_field "$md" name)"; [ -n "$skill" ] || skill="$(basename "$dir")"
    [[ "$skill" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ && "$skill" != *..* ]] || { echo "skill-import: skipping unsupported skill name in $source" >&2; continue; }
    desc="$(fm_field "$md" description)"
    desc="${desc//$'\t'/ }"
    printf '%s\t%s\tlocal\t%s\t%s\n' "$source" "$skill" "$rel" "$desc" >>"$OUT"
  done < <(find "$clone" -type f -name SKILL.md -not -path '*/.git/*' -print0 | sort -z)
}

emit_external() { # source clone_dir
  local source="$1" clone="$2" readme="$2/README.md"
  [ -f "$readme" ] || return 0
  # match list items: - [text](https://github.com/....) <sep> description
  # `|| true` guards against pipefail aborting the whole script when a
  # hybrid README happens to have zero github.com list-links.
  { grep -oE '^[[:space:]]*[-*][[:space:]]+\[[^]]+\]\(https://github\.com/[^)]+\)[^`]*' "$readme" || true; } | \
  while IFS= read -r line; do
    local url slug desc
    # first github link on the line wins (a trailing "*By [@user](...)*"
    # attribution link must not shadow the real entry)
    url="$(printf '%s' "$line" | grep -oE 'https://github\.com/[^)]+' | head -n1 || true)"
    [ -n "$url" ] || continue
    slug="$(basename "${url%/}")"
    case "$slug" in ''|.*|*/*|*..*) continue;; esac
    desc="$(printf '%s' "$line" | sed -E 's/^[^)]*\)[[:space:]]*[—–-]?[[:space:]]*//' | sed -E 's/[[:space:]]+$//')"
    printf '%s\t%s\texternal\t%s\t%s\n' "$source" "$slug" "$url" "$desc" >>"$OUT"
  done
}

printf 'source\tskill\tkind\tlocation\tdescription\n' >"$OUT"
errors=0
while IFS=$'\t' read -r name url type; do
  case "$name" in ''|\#*) continue;; esac
  clone="$(refresh_repo "$name" "$url")" || { errors=$((errors + 1)); continue; }
  emit_local "$name" "$clone"
  if [ "$type" = hybrid ]; then emit_external "$name" "$clone"; fi
done < "$SOURCES"
[ "$errors" -eq 0 ] || { echo 'skill-import: source refresh incomplete; original catalog preserved' >&2; exit 1; }
mv -f -- "$OUT" "$FINAL_OUT"
