#!/usr/bin/env bash
# kanban-status.sh — compact board overview.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./kanban-lib.sh
source "$HERE/kanban-lib.sh"

usage() {
  cat <<'EOF'
Usage: kanban-status.sh [--repo P] [--stage <s>] [--epic <ID>]
EOF
}

rest=()
kanban::strip_repo_flag rest "$@"
set -- "${rest[@]}"

FILTER_STAGE=""; FILTER_EPIC=""
while [ $# -gt 0 ]; do
  case "$1" in
    --stage) FILTER_STAGE="${2:-}"; shift 2 ;;
    --epic) FILTER_EPIC="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "kanban-status.sh: unknown arg: $1" >&2; usage >&2; exit 1 ;;
  esac
done

REPO="$(kanban::repo_root)"
BOARD="$(kanban::board_dir "$REPO")"

card_title() {
  local f="$1" t
  t="$(grep -m1 '^### ' "$f" 2>/dev/null | sed -E 's/^### +//')"
  [ -n "$t" ] || t="$(basename "$f" .md)"
  printf '%s' "$t"
}

declare -a all_dirs=()
if [ -d "$BOARD" ]; then
  for s in "${KANBAN_STAGES[@]}"; do
    [ -d "$BOARD/$s" ] && all_dirs+=("$s")
  done
  shopt -s nullglob
  for d in "$BOARD"/*/; do
    name="$(basename "$d")"
    case " ${KANBAN_STAGES[*]} " in
      *" $name "*) continue ;;
    esac
    all_dirs+=("$name")
  done
  shopt -u nullglob
fi

if [ -n "$FILTER_STAGE" ]; then
  keep=()
  for s in "${all_dirs[@]}"; do [ "$s" = "$FILTER_STAGE" ] && keep+=("$s"); done
  all_dirs=("${keep[@]}")
fi

declare -a OUT=()
GRAND_TOTAL=0

for stage in "${all_dirs[@]}"; do
  shopt -s nullglob
  cards=("$BOARD/$stage"/*.md)
  shopt -u nullglob

  if [ -n "$FILTER_EPIC" ]; then
    filtered=()
    for f in "${cards[@]}"; do
      base="$(basename "$f" .md)"
      case "$base" in
        "$FILTER_EPIC"|"$FILTER_EPIC"-*) filtered+=("$f") ;;
      esac
    done
    cards=("${filtered[@]}")
  fi

  n="${#cards[@]}"
  GRAND_TOTAL=$((GRAND_TOTAL + n))
  OUT+=("$(printf '%s (%d)' "$stage" "$n")")

  sorted=()
  if [ "$n" -gt 0 ]; then
    while IFS= read -r line; do sorted+=("$line"); done < <(printf '%s\n' "${cards[@]}" | sort)
  fi

  declare -A shown=()
  for f in "${sorted[@]}"; do
    base="$(basename "$f" .md)"
    [[ "$base" =~ ^[A-Za-z][A-Za-z0-9]*-[0-9]+-[0-9]{2}-.+$ ]] && continue
    id="$(kanban::extract_id "$base")"
    title="$(card_title "$f")"
    marker=""
    grep -q '^\*\*Subtasks:\*\*' "$f" 2>/dev/null && marker=" [epic]"
    OUT+=("$(printf '  %s  %s%s' "$id" "$title" "$marker")")
    shown["$base"]=1
    for g in "${sorted[@]}"; do
      gbase="$(basename "$g" .md)"
      if [[ "$gbase" =~ ^${id}-[0-9]{2}-.+$ ]]; then
        gid="$(kanban::extract_id "$gbase")"
        gtitle="$(card_title "$g")"
        OUT+=("$(printf '    %s  %s' "$gid" "$gtitle")")
        shown["$gbase"]=1
      fi
    done
  done
  for f in "${sorted[@]}"; do
    base="$(basename "$f" .md)"
    [ -n "${shown[$base]:-}" ] && continue
    id="$(kanban::extract_id "$base")"
    title="$(card_title "$f")"
    OUT+=("$(printf '  %s  %s' "$id" "$title")")
  done
  unset shown
done

if [ "$GRAND_TOTAL" -eq 0 ]; then
  echo "no cards"
else
  printf '%s\n' "${OUT[@]}"
fi
