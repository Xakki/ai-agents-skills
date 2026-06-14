#!/usr/bin/env bash
# UserPromptSubmit hook: record task start time + cancel any pending TG notifications
# from the previous turn.
#
# Reads JSON on stdin: { session_id, prompt, transcript_path, ... }
# Always exits 0 — must not block prompt submission.

set -uo pipefail

HOOK_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# shellcheck source=../skills/tg-notify/runtime.sh
source "$HOOK_DIR/../skills/tg-notify/runtime.sh"

STATE_DIR="$TG_STATE_DIR"
PENDING_DIR="$TG_PENDING_DIR"

mkdir -p "$STATE_DIR" "$PENDING_DIR" 2>/dev/null || exit 0

INPUT=$(cat)
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)
PROMPT=$(printf '%s' "$INPUT" | jq -r '.prompt // ""' 2>/dev/null)

# Cancel any pending notifications for this session (user is active again)
if [[ -d "$PENDING_DIR/$SESSION_ID" ]]; then
    rm -f "$PENDING_DIR/$SESSION_ID"/*.payload 2>/dev/null
    rmdir "$PENDING_DIR/$SESSION_ID" 2>/dev/null || true
fi

# Clear stopped marker — new turn means session is active again
rm -f "$STATE_DIR/$SESSION_ID.stopped" 2>/dev/null || true

# Record start time + (truncated) prompt as JSON for later use by Notification hook
# Truncate to 512 chars (multibyte-safe) — bash ${var:0:n} and head -c are byte-based.
NOW=$(date +%s)
PROMPT_TRIM=$(python3 -c '
import sys
t = sys.argv[1].replace("\n", " ").replace("\r", " ")
sys.stdout.write(t[:512])
' "$PROMPT")
jq -n --argjson ts "$NOW" --arg p "$PROMPT_TRIM" \
    '{started_at:$ts, prompt:$p}' \
    > "$STATE_DIR/$SESSION_ID.start" 2>/dev/null || true

exit 0
