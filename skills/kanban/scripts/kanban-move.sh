#!/usr/bin/env bash
# kanban-move.sh — move a kanban card between stage dirs.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./kanban-lib.sh
source "$HERE/kanban-lib.sh"

usage() {
  cat <<'EOF'
Usage: kanban-move.sh [--repo P] <ID | basename | path> <target-stage> [--force] [--approved]
EOF
}

rest=()
kanban::strip_repo_flag rest "$@"
set -- "${rest[@]}"

FORCE=0; APPROVED=0; REF=""; TARGET=""
while [ $# -gt 0 ]; do
  case "$1" in
    --force) FORCE=1; shift ;;
    --approved) APPROVED=1; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "kanban-move.sh: unknown flag: $1" >&2; usage >&2; exit 1 ;;
    *)
      if [ -z "$REF" ]; then REF="$1"
      elif [ -z "$TARGET" ]; then TARGET="$1"
      else echo "kanban-move.sh: extra argument: $1" >&2; usage >&2; exit 1
      fi
      shift
      ;;
  esac
done
[ -n "$REF" ] && [ -n "$TARGET" ] || { usage >&2; exit 1; }

REPO="$(kanban::repo_root)"
BOARD="$(kanban::board_dir "$REPO")"

# --- resolve the card reference across all board subdirs --------------------

resolve_card() {
  local repo="$1" ref="$2" board f base allcards=() matches=() exact=()
  board="$(kanban::board_dir "$repo")"

  if [ -f "$ref" ]; then
    CARD_PATH="$(cd "$(dirname "$ref")" && pwd)/$(basename "$ref")"
    return 0
  fi
  if [ -f "$repo/$ref" ]; then
    CARD_PATH="$repo/$ref"
    return 0
  fi

  shopt -s nullglob
  allcards=("$board"/*/*.md)
  shopt -u nullglob

  for f in "${allcards[@]}"; do
    base="$(basename "$f")"
    [ "$base" = "$ref" ] && matches+=("$f")
  done

  if [ "${#matches[@]}" -eq 0 ]; then
    for f in "${allcards[@]}"; do
      base="$(basename "$f" .md)"
      case "$base" in
        "$ref"|"$ref"-*) matches+=("$f") ;;
      esac
    done
    if [ "${#matches[@]}" -gt 1 ]; then
      for f in "${matches[@]}"; do
        base="$(basename "$f" .md)"
        [ "$base" = "$ref" ] && exact+=("$f")
      done
      [ "${#exact[@]}" -eq 1 ] && matches=("${exact[@]}")
    fi
  fi

  case "${#matches[@]}" in
    0) return 1 ;;
    1) CARD_PATH="${matches[0]}"; return 0 ;;
    *)
      echo "kanban-move.sh: ambiguous card reference '$ref', matches:" >&2
      for f in "${matches[@]}"; do echo "  $f" >&2; done
      return 2
      ;;
  esac
}

CARD_PATH=""
if resolve_card "$REPO" "$REF"; then
  :
else
  rc=$?
  if [ "$rc" -eq 2 ]; then exit 2; fi
  kanban::die "kanban-move.sh: no card found matching '$REF'" 2
fi

FROM_STAGE="$(basename "$(dirname "$CARD_PATH")")"
TO_STAGE="$TARGET"

to_idx="$(kanban::stage_index "$TO_STAGE")" || true
[ "$to_idx" -ge 0 ] || kanban::die "kanban-move.sh: unknown target stage '$TO_STAGE' (expected one of: ${KANBAN_STAGES[*]})" 2

from_idx="$(kanban::stage_index "$FROM_STAGE")" || true

step_ok=0
if [ "$from_idx" -ge 0 ]; then
  diff=$((to_idx - from_idx))
  [ "$diff" -eq 1 ] && step_ok=1
fi

if [ "$step_ok" -ne 1 ] && [ "$FORCE" -ne 1 ]; then
  kanban::die "kanban-move.sh: '$FROM_STAGE -> $TO_STAGE' is not a single forward step; use --force to skip a stage or move backward" 2
fi

if [ "$TO_STAGE" = done ] && [ "$APPROVED" -ne 1 ]; then
  kanban::die "kanban-move.sh: moving to done/ requires --approved (caller must hold explicit user approval at hand-off or recorded EPIC-scoped upfront autonomous authorization)" 2
fi

BASE_NOEXT="$(basename "$CARD_PATH" .md)"
if [[ "$BASE_NOEXT" =~ ^([A-Za-z][A-Za-z0-9]*-[0-9]+)-([0-9]{2})-.+$ ]]; then
  EPIC_ID="${BASH_REMATCH[1]}"
  IS_SUBTASK=1
else
  IS_SUBTASK=0
fi

if [ "$TO_STAGE" = done ] && [ "$IS_SUBTASK" -eq 1 ]; then
  PARENT_IN_DONE=0
  shopt -s nullglob
  for f in "$BOARD"/done/*.md; do
    pb="$(basename "$f" .md)"
    case "$pb" in
      "$EPIC_ID")
        PARENT_IN_DONE=1; break ;;
      "$EPIC_ID"-*)
        if [[ ! "$pb" =~ ^${EPIC_ID}-[0-9]{2}-.+$ ]]; then PARENT_IN_DONE=1; break; fi
        ;;
    esac
  done
  shopt -u nullglob
  if [ "$PARENT_IN_DONE" -ne 1 ] && [ "$FORCE" -ne 1 ]; then
    kanban::die "kanban-move.sh: subtask's parent epic '$EPIC_ID' is not in done/ yet; epic gates its subtasks (use --force to override)" 2
  fi
fi

if [ "$FROM_STAGE" = grooming ] && [ "$TO_STAGE" != grooming ]; then
  if grep -q '^\*\*Open questions:\*\*' "$CARD_PATH"; then
    kanban::die "kanban-move.sh: card still has an **Open questions:** section; resolve it into **Decisions:** first (see kanban-lint.sh)" 2
  fi
fi

# --- perform the move ---------------------------------------------------------

DEST_DIR="$BOARD/$TO_STAGE"
DEST_PATH="$DEST_DIR/$(basename "$CARD_PATH")"
GITMOVE="$HERE/../../git-move/git-move.sh"

if [ -f "$GITMOVE" ]; then
  bash "$GITMOVE" "$CARD_PATH" "$DEST_PATH" >/dev/null
else
  echo "kanban-move.sh: warning: git-move.sh not found at $GITMOVE; falling back to plain mv" >&2
  mkdir -p "$DEST_DIR"
  mv "$CARD_PATH" "$DEST_PATH"
fi

echo "$DEST_PATH"

verb=move
STEP="${FROM_STAGE}:${TO_STAGE}"
case "$STEP" in
  "grooming:todo")  verb=groom ;;
  "todo:progress")  verb=start ;;
  "progress:test")  verb=review ;;
  "test:ready")     verb=ready ;;
  "ready:done")     verb=done ;;
esac
ID_TOKEN="$(kanban::extract_id "$(basename "$DEST_PATH" .md)")"
echo "task: $verb $ID_TOKEN (${FROM_STAGE}→${TO_STAGE})" >&2
