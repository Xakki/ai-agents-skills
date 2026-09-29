#!/usr/bin/env bash
# Schedule entrypoint: opens a new byobu/tmux window and launches the inner runner.
# Invoked by `at` jobs. Idempotent re session existence.
#
# Universal: SCRIPT_DIR locates the sibling inner script (works from the plugin
# cache too). PROJECT_DIR/PROJECT_NAME come from the task-file argument — the
# card lives at <repo>/.claude/kanban/<stage>/<name>.md, so the repo is three
# levels up.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TASK_FILE="${1:?usage: $0 <absolute-path-to-task.md> <scope-id>}"
SCOPE_ID="${2:?usage: $0 <absolute-path-to-task.md> <scope-id>}"
TASK_FILE="$(realpath -e -- "$TASK_FILE")" || {
    printf 'ERROR: task file does not exist\n' >&2
    exit 1
}
TASK_BASENAME="$(basename -- "$TASK_FILE")"
TASK_NAME="$(basename -- "$TASK_FILE" .md)"
PROJECT_DIR="$(git -C "$(dirname -- "$TASK_FILE")" rev-parse --show-toplevel 2>/dev/null)" || {
    printf 'ERROR: task file is not inside a Git repository\n' >&2
    exit 1
}
PROJECT_DIR="$(realpath -e -- "$PROJECT_DIR")"
PROJECT_NAME="$(basename "$PROJECT_DIR")"

# shellcheck source=task-scope.sh
source "$SCRIPT_DIR/task-scope.sh"
LOG_DIR="${HOME:-/home/coder}/.local/state/claude-auto-runs/${PROJECT_NAME}"
task_scope_load "$PROJECT_DIR" "$LOG_DIR" "$SCOPE_ID" || exit 1
task_scope_contains "$TASK_BASENAME" || {
    printf 'ERROR: task is outside the approved scope: %s\n' "$TASK_BASENAME" >&2
    exit 1
}
task_scope_card_is_todo "$PROJECT_DIR" "$TASK_FILE" || {
    printf 'ERROR: scheduled task is no longer in todo/: %s\n' "$TASK_BASENAME" >&2
    exit 1
}

SOCKET="/tmp/tmux-1000/default"
SESSION="1"
INNER="$SCRIPT_DIR/run-claude-task-inner.sh"

export HOME="${HOME:-/home/coder}"
export USER="${USER:-coder}"
export PATH="$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# Ensure target session exists (in case byobu was killed).
if ! tmux -S "$SOCKET" has-session -t "$SESSION" 2>/dev/null; then
    tmux -S "$SOCKET" new-session -d -s "$SESSION"
fi

# Window name ≤10 chars: 2-letter project prefix + card ID (e.g. avito-fix /
# K-025-... -> "av:K-025"). Card IDs match ^[A-Za-z]+-[0-9]+ (K-025, FEAT-123);
# cards without an ID fall back to the first 7 chars of the name. Hard-capped to
# 10 chars, so an unusually long ID is truncated tail-first.
CARD_ID="$(printf '%s' "$TASK_NAME" | grep -oE '^[A-Za-z]+-[0-9]+' || printf '%s' "${TASK_NAME:0:7}")"
WIN_NAME="${PROJECT_NAME:0:2}:${CARD_ID}"
WIN_NAME="${WIN_NAME:0:10}"
tmux -S "$SOCKET" new-window -t "${SESSION}:" -n "$WIN_NAME" \
    "exec $(task_scope_shell_quote "$INNER") $(task_scope_shell_quote "$TASK_FILE") $(task_scope_shell_quote "$SCOPE_ID")"
