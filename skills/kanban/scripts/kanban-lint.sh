#!/usr/bin/env bash
# kanban-lint.sh — validate kanban card shape and board-level consistency.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./kanban-lib.sh
source "$HERE/kanban-lib.sh"

usage() {
  cat <<'EOF'
Usage: kanban-lint.sh [--repo P] [<ID|path> ...]
Lint kanban cards; default: every card on the board.
EOF
}

rest=()
kanban::strip_repo_flag rest "$@"
set -- "${rest[@]}"

case "${1:-}" in -h|--help) usage; exit 0 ;; esac

REPO="$(kanban::repo_root)"
BOARD="$(kanban::board_dir "$REPO")"
LOCKFILE="$(kanban::lock_file "$REPO")"

ERRORS=0
WARNINGS=0
err()  { echo "ERROR $1: $2"; ERRORS=$((ERRORS + 1)); }
warn() { echo "WARN $1: $2"; WARNINGS=$((WARNINGS + 1)); }

shopt -s nullglob
BOARD_CARDS=("$BOARD"/*/*.md)
shopt -u nullglob
DONE_DIR="$BOARD/done"
is_archived() {
  [[ "$1" == "$DONE_DIR"/* ]]
}
ALL_CARDS=()
for card in "${BOARD_CARDS[@]}"; do
  is_archived "$card" || ALL_CARDS+=("$card")
done

# --- resolve target cards ------------------------------------------------

declare -a TARGETS=()
if [ $# -eq 0 ]; then
  TARGETS=("${ALL_CARDS[@]}")
else
  for ref in "$@"; do
    if [ -f "$ref" ]; then
      TARGETS+=("$ref")
    elif [ -f "$REPO/$ref" ]; then
      TARGETS+=("$REPO/$ref")
    else
      found=""
      # Prefer an active card for an implicit reference; only fall back to an
      # archived match so it can be excluded by the archive filter below.
      for f in "${ALL_CARDS[@]}"; do
        bmd="$(basename "$f")"
        base="$(basename "$f" .md)"
        if [ "$bmd" = "$ref" ] || [ "$base" = "$ref" ]; then
          found="$f"
          break
        fi
      done
      if [ -z "$found" ]; then
        for f in "${BOARD_CARDS[@]}"; do
          bmd="$(basename "$f")"
          base="$(basename "$f" .md)"
          if [ "$bmd" = "$ref" ] || [ "$base" = "$ref" ]; then
            found="$f"
            break
          fi
        done
      fi
      if [ -n "$found" ]; then
        TARGETS+=("$found")
      else
        err "$ref" "no matching card found on the board"
      fi
    fi
  done
fi

# Done cards are archived and excluded even when passed as explicit paths.
ACTIVE_TARGETS=()
for f in "${TARGETS[@]}"; do
  is_archived "$f" || ACTIVE_TARGETS+=("$f")
done
TARGETS=("${ACTIVE_TARGETS[@]}")

# --- known prefixes from the lock file -----------------------------------

declare -A KNOWN_PREFIX=()
if [ -f "$LOCKFILE" ]; then
  while IFS='=' read -r k v; do
    case "$k" in ''|\#*|prefix) continue ;; esac
    [ -n "$k" ] && KNOWN_PREFIX["$k"]=1
  done < "$LOCKFILE"
fi

# --- board-level: duplicate IDs across stages ----------------------------

declare -A ID_SEEN_AT=()
for f in "${ALL_CARDS[@]}"; do
  base="$(basename "$f" .md)"
  id="$(kanban::extract_id "$base")"
  if [ -n "${ID_SEEN_AT[$id]:-}" ]; then
    err "$f" "duplicate card ID '$id' (also at ${ID_SEEN_AT[$id]})"
  else
    ID_SEEN_AT["$id"]="$f"
  fi
done

# --- per-card checks ------------------------------------------------------

for f in "${TARGETS[@]}"; do
  [ -f "$f" ] || continue
  base="$(basename "$f" .md)"
  stage="$(basename "$(dirname "$f")")"

  if [[ ! "$base" =~ ^[A-Za-z][A-Za-z0-9]*-[0-9]+(-[0-9]{2})?-.+$ ]]; then
    err "$f" "filename does not match <PREFIX>-<NUM>[-<SUB>]-<slug>.md"
  fi

  prefix="$(kanban::card_prefix "$base")"
  if [ -n "$prefix" ] && [ -z "${KNOWN_PREFIX[$prefix]:-}" ]; then
    warn "$f" "prefix '$prefix' is not registered in the lock file"
  fi

  grep -q '^### ' "$f" || err "$f" "missing a '### ' title line"

  for section in '**Criticality:**' '**TAGS:**' '**Description:**' '**Problem:**' '**Impact:**' '**Recommendation:**' '**Acceptance Criteria:**'; do
    grep -qF "$section" "$f" || err "$f" "missing required section $section"
  done

  has_open_q=0
  grep -q '^\*\*Open questions:\*\*' "$f" && has_open_q=1

  if [ "$stage" != "grooming" ] && [ "$has_open_q" -eq 1 ]; then
    err "$f" "contains **Open questions:** outside grooming/"
  fi
  if [ "$stage" = "grooming" ] && [ "$has_open_q" -eq 0 ]; then
    warn "$f" "grooming/ card has no **Open questions:** section"
  fi

  if grep -q '^\*\*Subtasks:\*\*' "$f"; then
    in_block=0
    while IFS= read -r line; do
      if [[ "$line" =~ ^\*\*Subtasks:\*\* ]]; then
        in_block=1
        continue
      fi
      if [ "$in_block" -eq 1 ]; then
        if [[ "$line" =~ ^\*\* ]]; then break; fi
        sid="$(printf '%s' "$line" | grep -oE '[A-Za-z][A-Za-z0-9]*-[0-9]+(-[0-9]{2})?' | head -n1 || true)"
        if [ -n "$sid" ]; then
          exists=0
          for g in "${ALL_CARDS[@]}"; do
            gbase="$(basename "$g" .md)"
            case "$gbase" in
              "$sid"|"$sid"-*) exists=1; break ;;
            esac
          done
          [ "$exists" -eq 1 ] || warn "$f" "subtask '$sid' listed but no matching card found"
        fi
      fi
    done < "$f"
  fi

  if [ -n "$prefix" ]; then
    numstr="${base#"$prefix"-}"
    numstr="${numstr%%[!0-9]*}"
    if [ -n "$numstr" ]; then
      numi=$((10#$numstr))
      ctr="$(kanban::lock_get_counter "$LOCKFILE" "$prefix")"
      # ctr=0 means the prefix has no counter entry at all yet (never
      # allocated via kanban-id.sh) — nothing to have drifted from; that
      # case is already covered by the "not registered" warning above.
      if [ "$ctr" -gt 0 ] && [ "$numi" -gt "$ctr" ]; then
        warn "$f" "card number $numi exceeds lock counter $ctr for prefix '$prefix' (counter drift)"
      fi
    fi
  fi
done

echo "kanban-lint: ${#TARGETS[@]} card(s) checked, $ERRORS error(s), $WARNINGS warning(s)"
if [ "$ERRORS" -eq 0 ]; then
  exit 0
else
  exit 2
fi
