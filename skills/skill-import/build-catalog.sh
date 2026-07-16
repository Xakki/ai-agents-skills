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
    dir="${md%/SKILL.md}"
    if [ "$dir" = "$clone" ]; then rel="."; else rel="${dir#"$clone"/}"; fi
    skill="$(fm_field "$md" name)"; [ -n "$skill" ] || skill="$(basename "$dir")"
    case "$skill" in ''|.*|*/*|*..*) echo "skill-import: skipping unsafe skill name '$skill' in $source" >&2; continue;; esac
    desc="$(fm_field "$md" description)"
    printf '%s\t%s\tlocal\t%s\t%s\n' "$source" "$skill" "$rel" "$desc" >>"$OUT"
  done < <(find "$clone" -name SKILL.md -not -path '*/.git/*' | sort)
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
while IFS=$'\t' read -r name url type; do
  case "$name" in ''|\#*) continue;; esac
  clone="$(refresh_repo "$name" "$url")" || continue
  emit_local "$name" "$clone"
  if [ "$type" = hybrid ]; then emit_external "$name" "$clone"; fi
done < "$SOURCES"
