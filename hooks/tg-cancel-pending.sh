#!/usr/bin/env bash
# Cancel any pending TG notifications for this session.
# Wired to PreToolUse, Stop, SessionEnd — all signal "user is active / turn done".
#
# Reads JSON on stdin: { session_id, ... }
# Always exits 0 — must not block tool execution or session lifecycle.

set -uo pipefail

HOOK_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# shellcheck source=../skills/tg-notify/runtime.sh
source "$HOOK_DIR/../skills/tg-notify/runtime.sh"

PENDING_DIR="$TG_PENDING_DIR"
[[ -d "$PENDING_DIR" ]] || exit 0

SESSION_ID=$(jq -r '.session_id // "unknown"' 2>/dev/null) || exit 0

if [[ -d "$PENDING_DIR/$SESSION_ID" ]]; then
    rm -f "$PENDING_DIR/$SESSION_ID"/*.payload 2>/dev/null
    rmdir "$PENDING_DIR/$SESSION_ID" 2>/dev/null || true
fi

exit 0
