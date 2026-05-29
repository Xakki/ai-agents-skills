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

TASK_FILE="${1:?usage: $0 <absolute-path-to-task.md>}"
TASK_NAME="$(basename "$TASK_FILE" .md)"
PROJECT_DIR="$(cd "$(dirname "$TASK_FILE")/../../.." && pwd)"
PROJECT_NAME="$(basename "$PROJECT_DIR")"

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

WIN_NAME="${PROJECT_NAME}:${TASK_NAME:0:25}"
tmux -S "$SOCKET" new-window -t "${SESSION}:" -n "$WIN_NAME" \
    "exec '$INNER' '$TASK_FILE'"
