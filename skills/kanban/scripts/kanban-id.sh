#!/usr/bin/env bash
# kanban-id.sh — allocate / peek kanban card IDs.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./kanban-lib.sh
source "$HERE/kanban-lib.sh"

usage() {
  cat <<'EOF'
Usage:
  kanban-id.sh [--repo P] next  [<PREFIX>]      allocate+persist a new ID, e.g. K-043
  kanban-id.sh [--repo P] epic  [<PREFIX>]      allocate a new EPIC ID, e.g. EPIC-043
  kanban-id.sh [--repo P] sub   <EPIC-ID>       next free subtask number, e.g. K-043-02
  kanban-id.sh [--repo P] peek  [<PREFIX>]      last used ID; allocates nothing
  kanban-id.sh [--repo P] prefix                print the default prefix (confirmation required
                                                 on first use — see set-prefix / KANBAN_ASSUME_YES)
  kanban-id.sh [--repo P] set-prefix <PREFIX>   confirm+persist the project's default prefix
EOF
}

rest=()
kanban::strip_repo_flag rest "$@"
set -- "${rest[@]}"

case "${1:-}" in -h|--help) usage; exit 0 ;; esac
[ $# -ge 1 ] || { usage >&2; exit 1; }
cmd="$1"; shift

REPO="$(kanban::repo_root)"
LOCKFILE="$(kanban::lock_file "$REPO")"

case "$cmd" in
  next)
    prefix="${1:-}"
    if [ -n "$prefix" ]; then
      # An explicit --prefix IS the confirmation — persist it as the
      # project default only if none is recorded yet (never overrides an
      # already-confirmed different default).
      kanban::persist_prefix_if_unset "$REPO" "$prefix"
    else
      prefix="$(kanban::resolve_and_reserve_prefix "$REPO")"
    fi
    kanban::allocate_next_id "$REPO" "$prefix"
    ;;

  epic)
    # Keep accepting the historical optional prefix argument for CLI
    # compatibility; epic IDs always occupy the reserved EPIC namespace.
    [ $# -le 1 ] || kanban::die "kanban-id.sh epic: at most one legacy prefix argument is allowed" 1
    kanban::allocate_next_id "$REPO" "EPIC"
    ;;

  sub)
    [ $# -ge 1 ] || kanban::die "kanban-id.sh sub: <EPIC-ID> required" 1
    epic="$1"
    kanban::epic_exists "$REPO" "$epic" \
      || kanban::die "kanban-id.sh: no card found for epic '$epic' on the board (subtask of a non-existent epic)" 2
    kanban::lock_ensure "$LOCKFILE"
    kanban::_lock_acquire "$LOCKFILE"
    max="$(kanban::next_sub "$REPO" "$epic")"
    kanban::_lock_release
    next=$((max + 1))
    [ "$next" -le 99 ] || kanban::die "kanban-id.sh: subtask numbers exhausted (>99) for '$epic'" 2
    printf '%s-%02d\n' "$epic" "$next"
    ;;

  peek)
    prefix="${1:-}"
    [ -n "$prefix" ] || prefix="$(kanban::lock_get_prefix "$LOCKFILE")"
    # Read-only fallback for a legacy board (cards on disk, no kanban.lock
    # yet): peek must answer from the board's dominant prefix without
    # writing anything — reservation only happens on an actual allocation.
    [ -n "$prefix" ] || prefix="$(kanban::dominant_board_prefix "$REPO")"
    [ -n "$prefix" ] || kanban::die "kanban-id.sh: no default prefix reserved yet for this repo" 2
    cur="$(kanban::lock_get_counter "$LOCKFILE" "$prefix")"
    maxcard="$(kanban::max_card_num "$REPO" "$prefix")"
    val="$cur"
    [ "$maxcard" -gt "$val" ] && val="$maxcard"
    if [ "$val" -le 0 ]; then
      kanban::die "kanban-id.sh: no IDs allocated yet for prefix '$prefix'" 2
    fi
    width="$(kanban::prefix_width "$REPO" "$prefix")"
    printf '%s-%0*d\n' "$prefix" "$width" "$val"
    ;;

  prefix)
    kanban::resolve_and_reserve_prefix "$REPO"
    ;;

  set-prefix)
    [ $# -ge 1 ] || kanban::die "kanban-id.sh set-prefix: <PREFIX> required" 1
    newprefix="$1"
    kanban::valid_prefix_shape "$newprefix" \
      || kanban::die "kanban-id.sh: '$newprefix' is not a valid prefix (letters/digits, starting with a letter)" 1
    kanban::_persist_prefix "$REPO" "$newprefix" "set-prefix"
    printf '%s\n' "$newprefix"
    ;;

  *)
    echo "kanban-id.sh: unknown subcommand '$cmd'" >&2
    usage >&2
    exit 1
    ;;
esac
