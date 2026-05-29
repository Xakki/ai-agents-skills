#!/usr/bin/env bash
# Pretty-print a claude session JSONL as a readable transcript.
#
# Run this from inside the target repo — it resolves the project from the
# current git root (falls back to $PWD). The script itself lives in the plugin
# cache, so it does NOT derive the project from its own location.
#
# Usage (from the repo root):
#   "${CLAUDE_PLUGIN_ROOT}/scripts/view-task-history.sh" <session-id>
#   "${CLAUDE_PLUGIN_ROOT}/scripts/view-task-history.sh" <task-name>   # last matching auto-run
#   "${CLAUDE_PLUGIN_ROOT}/scripts/view-task-history.sh" --list        # list recent auto-runs
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
PROJECT_NAME="$(basename "$PROJECT_DIR")"
CLAUDE_PROJECT_PATH="$(printf '%s' "$PROJECT_DIR" | tr '/' '-')"

LOG_DIR="${HOME:-/home/coder}/.local/state/claude-auto-runs/${PROJECT_NAME}"
PROJ_DIR="${HOME:-/home/coder}/.claude/projects/${CLAUDE_PROJECT_PATH}"

if [ "${1:-}" = "--list" ] || [ -z "${1:-}" ]; then
    echo "Recent auto-runs in $LOG_DIR:"
    echo
    if compgen -G "$LOG_DIR/*.meta.log" >/dev/null; then
        for m in $(ls -1t "$LOG_DIR"/*.meta.log); do
            sid=$(grep -m1 '^=== SESSION' "$m" | awk '{print $NF}')
            task=$(grep -m1 '^=== TASK' "$m" | sed 's/^=== TASK *: *//')
            ts=$(basename "$m" | sed -E 's/^([0-9]{8}_[0-9]{6}).*/\1/')
            printf "  %s  %-40s  %s\n" "$ts" "$task" "$sid"
        done
    else
        echo "  (none yet)"
    fi
    exit 0
fi

ARG="$1"
SESSION_FILE=""

# Try as session ID first
if [ -f "$PROJ_DIR/$ARG.jsonl" ]; then
    SESSION_FILE="$PROJ_DIR/$ARG.jsonl"
fi

# Try as task name → most recent meta.log → session id
if [ -z "$SESSION_FILE" ]; then
    META=$(ls -1t "$LOG_DIR"/*"$ARG"*.meta.log 2>/dev/null | head -1)
    if [ -n "$META" ]; then
        SID=$(grep -m1 '^=== SESSION' "$META" | awk '{print $NF}')
        if [ -n "$SID" ] && [ -f "$PROJ_DIR/$SID.jsonl" ]; then
            SESSION_FILE="$PROJ_DIR/$SID.jsonl"
        fi
    fi
fi

if [ -z "$SESSION_FILE" ] || [ ! -f "$SESSION_FILE" ]; then
    echo "ERROR: no session file found for '$ARG'" >&2
    echo "Try: $0 --list" >&2
    exit 1
fi

echo "=== session: $SESSION_FILE"
echo

python3 - "$SESSION_FILE" <<'PY'
import json, sys, textwrap

path = sys.argv[1]
def trim(s, n=600):
    s = str(s)
    return s if len(s) <= n else s[:n] + f" …(+{len(s)-n} chars)"

with open(path) as f:
    for i, line in enumerate(f):
        try:
            obj = json.loads(line)
        except Exception:
            continue
        t = obj.get("type", "?")
        msg = obj.get("message", {})
        role = msg.get("role", "")
        content = msg.get("content", "")
        if t in ("attachment", "ai-title", "last-prompt", "permission-mode", "file-history-snapshot"):
            continue
        header = f"--- {i:03d} [{t}/{role}] ---"
        if isinstance(content, list):
            parts = []
            for c in content:
                ct = c.get("type")
                if ct == "text":
                    parts.append(trim(c.get("text", "")))
                elif ct == "tool_use":
                    name = c.get("name", "?")
                    inp = json.dumps(c.get("input", {}), ensure_ascii=False)
                    parts.append(f"[tool_use {name}] {trim(inp, 400)}")
                elif ct == "tool_result":
                    res = c.get("content", "")
                    if isinstance(res, list):
                        res = " ".join((x.get("text","") if isinstance(x, dict) else str(x)) for x in res)
                    parts.append(f"[tool_result] {trim(res, 400)}")
                elif ct == "thinking":
                    parts.append(f"[thinking] {trim(c.get('thinking',''), 300)}")
            content = "\n  ".join(parts)
        elif isinstance(content, str):
            content = trim(content)
        print(header)
        for ln in str(content).splitlines():
            print("  " + ln)
        print()
PY
