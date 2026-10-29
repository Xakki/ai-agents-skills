#!/usr/bin/env bash
# Checkpoint an unfinished scheduled card: snapshot its working-tree changes to a
# side branch task/<card> from a throw-away index and write .parked/<card>.
# The current branch, the real index and the working tree are never modified.
# Usable only inside an approved scheduled run: SCHEDULE_SCOPE_ID must name a
# valid scope that lists the card.
#
# Args: <CARD> <BASE_BRANCH> <BASELINE_FILE> <SESSION_ID> <LOG_DIR> <REASON>
# REASON: qa-fail | review-fail | blocker | question | merge-conflict
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=task-scope.sh
source "$SCRIPT_DIR/task-scope.sh"

if [ "$#" -ne 6 ]; then
    printf 'Usage: %s <card> <base-branch> <baseline> <session> <log-dir> <reason>\n' "$0" >&2
    exit 2
fi
CARD="$1"; BASE_BRANCH="$2"; LOG_DIR="$5"

SCOPE_ID="${SCHEDULE_SCOPE_ID:-}"
[ -n "$SCOPE_ID" ] || { printf '%s\n' 'ERROR: parking refused: SCHEDULE_SCOPE_ID is not set; park only from an approved scheduled run' >&2; exit 1; }
REPO="$(git -C "$(dirname -- "$CARD")" rev-parse --show-toplevel 2>/dev/null)" || {
    printf '%s\n' 'ERROR: parking refused: card is not inside a Git repository' >&2; exit 1; }
task_scope_load "$REPO" "$LOG_DIR" "$SCOPE_ID" || exit 1
task_scope_contains "$(basename -- "$CARD")" || {
    printf '%s\n' 'ERROR: parking refused: card is outside the approved scope' >&2; exit 1; }
[ "$BASE_BRANCH" = "$SCOPE_BASE_BRANCH" ] || {
    printf '%s\n' 'ERROR: parking refused: base branch differs from the approved scope' >&2; exit 1; }

exec python3 -I "$SCRIPT_DIR/park_task.py" "$@"
