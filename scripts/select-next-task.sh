#!/usr/bin/env bash
# Select the next runnable card from the exact approved scope, in recorded order.
# A card is BLOCKED if it references a task currently parked in PARKED_DIR.
# Args: <REPO> <PARKED_DIR> <JUST_FINISHED_NAME> <SCOPE_ID>
# Prints: approved card basename, or "none". Invalid scope exits non-zero.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=task-scope.sh
source "$SCRIPT_DIR/task-scope.sh"

[ "$#" -eq 4 ] || {
    printf 'Usage: %s <REPO> <PARKED_DIR> <JUST_FINISHED_NAME> <SCOPE_ID>\n' "$0" >&2
    exit 2
}
REPO="$(git -C "$1" rev-parse --show-toplevel 2>/dev/null)" || {
    printf 'scope error: cannot resolve repository root\n' >&2
    exit 1
}
REPO="$(realpath -e -- "$REPO")"
PARKED_DIR="$2"
JUST_FINISHED="$3"
SCOPE_ID="$4"
PROJECT_NAME="$(basename -- "$REPO")"
LOG_DIR="${HOME:?HOME must be set}/.local/state/claude-auto-runs/${PROJECT_NAME}"
task_scope_load "$REPO" "$LOG_DIR" "$SCOPE_ID" || exit 1
if [ -n "$JUST_FINISHED" ] && ! task_scope_contains "$JUST_FINISHED"; then
    printf 'scope error: completed card is outside the approved scope\n' >&2
    exit 1
fi

PARKED_IDS=()
if [ -d "$PARKED_DIR" ]; then
    shopt -s nullglob
    for file in "$PARKED_DIR"/*; do
        [ -f "$file" ] || continue
        name="$(basename -- "$file")"
        id="$(printf '%s' "$name" | grep -oE '^[A-Za-z]+-[0-9]+' || printf '%s' "$name")"
        PARKED_IDS+=("$id")
    done
    shopt -u nullglob
fi

is_blocked() {
    local card="$1" id
    [ "${#PARKED_IDS[@]}" -gt 0 ] || return 1
    for id in "${PARKED_IDS[@]}"; do
        if grep -iqE '(depends on|blocked by|зависит от|блокируется)' "$card" 2>/dev/null \
            && grep -qF "$id" "$card" 2>/dev/null; then
            return 0
        fi
    done
    return 1
}

TODO_DIR="$(task_scope_todo_dir "$REPO")" || exit 1
START_NEXT=true
if [ -n "$JUST_FINISHED" ]; then
    START_NEXT=false
fi
for card_name in "${SCOPE_CARDS[@]}"; do
    if [ "$START_NEXT" != true ]; then
        [ "$card_name" = "$JUST_FINISHED" ] && START_NEXT=true
        continue
    fi
    card="$TODO_DIR/$card_name"
    [ -f "$card" ] || continue
    is_blocked "$card" && continue
    printf '%s\n' "$card_name"
    exit 0
done
printf 'none\n'
