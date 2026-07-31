#!/usr/bin/env bash
# kanban-new.sh — create a new kanban card from the task template.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./kanban-lib.sh
source "$HERE/kanban-lib.sh"

usage() {
  cat <<'EOF'
Usage:
  kanban-new.sh [--repo P] --title "Title" [--stage todo|grooming] [--prefix P]
                [--epic] [--sub <EPIC-ID>]
                [--crit Blocking|High|Medium|Minor] [--tag feature|bug-fix|tech-debt]
EOF
}

rest=()
kanban::strip_repo_flag rest "$@"
set -- "${rest[@]}"

TITLE=""; STAGE="todo"; PREFIX_OVERRIDE=""; IS_EPIC=0; SUB_EPIC=""; CRIT=""; TAG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --title) TITLE="${2:-}"; shift 2 ;;
    --stage) STAGE="${2:-}"; shift 2 ;;
    --prefix) PREFIX_OVERRIDE="${2:-}"; shift 2 ;;
    --epic) IS_EPIC=1; shift ;;
    --sub) SUB_EPIC="${2:-}"; shift 2 ;;
    --crit) CRIT="${2:-}"; shift 2 ;;
    --tag) TAG="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "kanban-new.sh: unknown arg: $1" >&2; usage >&2; exit 1 ;;
  esac
done

[ -n "$TITLE" ] || kanban::die "kanban-new.sh: --title is required" 1
case "$STAGE" in
  todo|grooming) ;;
  *) kanban::die "kanban-new.sh: --stage must be todo or grooming (got '$STAGE')" 1 ;;
esac
if [ "$IS_EPIC" -eq 1 ] && [ -n "$SUB_EPIC" ]; then
  kanban::die "kanban-new.sh: --epic and --sub are mutually exclusive" 1
fi
if [ -n "$CRIT" ]; then
  case "$CRIT" in
    Blocking|High|Medium|Minor) ;;
    *) kanban::die "kanban-new.sh: --crit must be one of Blocking|High|Medium|Minor" 1 ;;
  esac
fi
if [ -n "$TAG" ]; then
  case "$TAG" in
    feature|bug-fix|tech-debt) ;;
    *) kanban::die "kanban-new.sh: --tag must be one of feature|bug-fix|tech-debt" 1 ;;
  esac
fi

REPO="$(kanban::repo_root)"
LOCKFILE="$(kanban::lock_file "$REPO")"
TEMPLATE="$HERE/../task-template.md"
[ -f "$TEMPLATE" ] || kanban::die "kanban-new.sh: template not found: $TEMPLATE" 2

# --- ID allocation -----------------------------------------------------------

if [ -n "$SUB_EPIC" ]; then
  kanban::epic_exists "$REPO" "$SUB_EPIC" \
    || kanban::die "kanban-new.sh: no card found for epic '$SUB_EPIC' on the board" 2
  kanban::lock_ensure "$LOCKFILE"
  kanban::_lock_acquire "$LOCKFILE"
  maxsub="$(kanban::next_sub "$REPO" "$SUB_EPIC")"
  kanban::_lock_release
  nextsub=$((maxsub + 1))
  [ "$nextsub" -le 99 ] || kanban::die "kanban-new.sh: subtask numbers exhausted (>99) for '$SUB_EPIC'" 2
  ID="$(printf '%s-%02d' "$SUB_EPIC" "$nextsub")"
else
  if [ -n "$PREFIX_OVERRIDE" ]; then
    PFX="$PREFIX_OVERRIDE"
    # An explicit --prefix IS the confirmation — persist it as the project
    # default only if none is recorded yet.
    kanban::persist_prefix_if_unset "$REPO" "$PFX"
  else
    PFX="$(kanban::resolve_and_reserve_prefix "$REPO")"
  fi
  ID="$(kanban::allocate_next_id "$REPO" "$PFX")"
fi

# --- slug --------------------------------------------------------------------

SLUG="$(printf '%s' "$TITLE" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"
if [ "${#SLUG}" -gt 40 ]; then
  SLUG="${SLUG:0:40}"
  case "$SLUG" in *-*) SLUG="${SLUG%-*}" ;; esac
fi
[ -n "$SLUG" ] || SLUG="task"

# --- render --------------------------------------------------------------------

CONTENT="$(cat "$TEMPLATE")"
CONTENT="${CONTENT/\#\#\# \[Task Title\]/### $TITLE}"
[ -n "$CRIT" ] && CONTENT="${CONTENT/\[Blocking | High | Medium | Minor\]/$CRIT}"
[ -n "$TAG" ] && CONTENT="${CONTENT/- tech-debt | feature | bug-fix/- $TAG}"

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
printf '%s\n' "$CONTENT" > "$TMP"

if [ "$STAGE" = todo ]; then
  TMP2="$(mktemp)"
  awk '
    /^\*\*Open questions:\*\*/ { skip=1; next }
    /^\*\*Decisions:\*\*/      { skip=0 }
    skip { next }
    { print }
  ' "$TMP" > "$TMP2"
  mv "$TMP2" "$TMP"
fi

if [ "$IS_EPIC" -eq 1 ]; then
  {
    echo ""
    echo "**Subtasks:**"
    echo "- ${ID}-01 — <purpose>"
    echo "- ${ID}-02 — <purpose>"
    echo ""
    echo "**Integration checklist:**"
    echo "- Restart from a clean state and refresh all data (migrations/imports)"
    echo "- Run the full quality gate (lint, tests, coverage, build)"
  } >> "$TMP"
fi

# --- write ---------------------------------------------------------------------

STAGE_DIR="$(kanban::board_dir "$REPO")/$STAGE"
mkdir -p "$STAGE_DIR"
CARD_PATH="$STAGE_DIR/${ID}-${SLUG}.md"
[ -e "$CARD_PATH" ] && kanban::die "kanban-new.sh: refusing to overwrite existing card: $CARD_PATH" 2

cp "$TMP" "$CARD_PATH"

if git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C "$REPO" add -- "$CARD_PATH"
  [ -f "$LOCKFILE" ] && git -C "$REPO" add -- "$LOCKFILE"
fi

echo "$CARD_PATH"
