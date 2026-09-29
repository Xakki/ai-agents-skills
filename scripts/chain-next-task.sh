#!/usr/bin/env bash
# Select and enqueue exactly one next card from an approved scope manifest.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=task-scope.sh
source "$SCRIPT_DIR/task-scope.sh"

usage() {
    printf 'Usage: %s <REPO> <PARKED_DIR> <JUST_FINISHED_NAME> <SCOPE_ID> <BASELINE_FILE>\n' "$0" >&2
}

[ "$#" -eq 5 ] || { usage; exit 2; }
REPO="$(git -C "$1" rev-parse --show-toplevel 2>/dev/null)" || {
    printf '[chain] ERROR: cannot resolve repository root\n' >&2
    echo 'AUTO-RUN-NEXT: none'
    exit 1
}
REPO="$(realpath -e -- "$REPO")"
PARKED_DIR="$2"
JUST_FINISHED="$3"
SCOPE_ID="$4"
BASELINE_FILE="$5"
PROJECT_NAME="$(basename -- "$REPO")"
LOG_DIR="${HOME:-/home/coder}/.local/state/claude-auto-runs/${PROJECT_NAME}"

if ! task_scope_load "$REPO" "$LOG_DIR" "$SCOPE_ID"; then
    echo 'AUTO-RUN-NEXT: none'
    exit 1
fi
if [ -n "$JUST_FINISHED" ] && ! task_scope_contains "$JUST_FINISHED"; then
    printf '[chain] ERROR: completed card is outside the approved scope: %s\n' "$JUST_FINISHED" >&2
    echo 'AUTO-RUN-NEXT: none'
    exit 1
fi

if ! command -v systemctl >/dev/null 2>&1 || ! systemctl is-active --quiet atd; then
    echo '[chain] WARN: atd inactive — chain stops'
    echo 'AUTO-RUN-NEXT: none'
    exit 0
fi
if [ ! -f "$BASELINE_FILE" ]; then
    printf '[chain] WARN: baseline file is missing — chain stops\n' >&2
    echo 'AUTO-RUN-NEXT: none'
    exit 0
fi

CURRENT_PATHS="$(git -C "$REPO" status --porcelain 2>/dev/null | cut -c4- | sort -u)"
BASELINE_PATHS="$(cut -c4- "$BASELINE_FILE" 2>/dev/null | sort -u)"
if [ -n "$CURRENT_PATHS" ]; then
    NEW_DIRT="$(comm -23 <(printf '%s\n' "$CURRENT_PATHS") <([ -n "$BASELINE_PATHS" ] && printf '%s\n' "$BASELINE_PATHS" || true))"
    if [ -n "$NEW_DIRT" ]; then
        printf '[chain] WARN: uncommitted task changes beyond baseline — chain stops\n'
        printf '%s\n' "$NEW_DIRT"
        echo 'AUTO-RUN-NEXT: none'
        exit 0
    fi
fi

NEXT="$("$SCRIPT_DIR/select-next-task.sh" "$REPO" "$PARKED_DIR" "$JUST_FINISHED" "$SCOPE_ID")"
SELECT_RC=$?
if [ "$SELECT_RC" -ne 0 ]; then
    printf '[chain] ERROR: scoped selection failed — chain stops\n' >&2
    echo 'AUTO-RUN-NEXT: none'
    exit 1
fi
if [ "$NEXT" = "none" ]; then
    echo '[chain] no eligible card remains in the approved scope'
    echo 'AUTO-RUN-NEXT: none'
    exit 0
fi
if ! task_scope_contains "$NEXT"; then
    printf '[chain] ERROR: selector returned an out-of-scope card: %s\n' "$NEXT" >&2
    echo 'AUTO-RUN-NEXT: none'
    exit 1
fi

TODO_DIR="$(task_scope_todo_dir "$REPO")" || {
    echo 'AUTO-RUN-NEXT: none'
    exit 1
}
TASK_FILE="$TODO_DIR/$NEXT"
[ -f "$TASK_FILE" ] || {
    printf '[chain] ERROR: selected card disappeared before enqueue: %s\n' "$NEXT" >&2
    echo 'AUTO-RUN-NEXT: none'
    exit 1
}

RUNNER="$SCRIPT_DIR/run-claude-task.sh"
AT_COMMAND="$(task_scope_job_command "$RUNNER" "$TASK_FILE" "$SCOPE_ID")"
AT_TIME="$(date -d '+20 minutes' +%Y%m%d%H%M 2>/dev/null)" || {
    printf '[chain] WARN: cannot calculate at time — chain stops\n' >&2
    echo 'AUTO-RUN-NEXT: none'
    exit 0
}
AT_OUT="$(printf '%s\n' "$AT_COMMAND" | at -t "$AT_TIME" 2>&1)"
AT_RC=$?
[ -z "$AT_OUT" ] || printf '%s\n' "$AT_OUT"
if [ "$AT_RC" -ne 0 ]; then
    printf '[chain] WARN: at failed (rc=%s) for %s\n' "$AT_RC" "$NEXT" >&2
    echo 'AUTO-RUN-NEXT: none'
    exit 0
fi
printf '[chain] enqueued next approved card at +20min: %s\n' "$NEXT"
printf 'AUTO-RUN-NEXT: %s\n' "$NEXT"
