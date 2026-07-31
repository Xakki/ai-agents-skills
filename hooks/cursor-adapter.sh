#!/usr/bin/env bash
# Cursor hook adapter: normalizes a Cursor hook payload (stdin) into the
# field shape hooks/*.sh already expect (session_id, prompt, transcript_path,
# cwd, message), then execs the target script with the normalized payload on
# ITS stdin. Never blocks the agent loop: falls back to passing the raw
# payload through on any transform error, and always exits 0.
#
# Usage (from hooks/cursor-hooks.json):
#   "${CURSOR_PLUGIN_ROOT}"/hooks/cursor-adapter.sh <target-script-name>
#
# Field mapping (see docs/superpowers/specs/2026-07-31-cursor-plugin-design.md
# "Hook adapter design" for the sourced rationale — verify against that doc
# and the live Cursor hooks reference before changing this mapping):
#   session_id       <- .conversation_id // .session_id // "unknown"
#   prompt           <- .prompt // ""
#   transcript_path  <- .transcript_path // ""
#   cwd              <- .cwd // .workspace_roots[0] // "" (let target fall back to $PWD)
#   message          <- .message // .agent_message // ""

set -uo pipefail
HOOK_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

TARGET="${1:-}"
case "$TARGET" in
  abbr-inject.sh|tg-prompt-start.sh|tg-on-stop.sh|tg-cancel-pending.sh) ;;
  *) cat >/dev/null; exit 0 ;;
esac

[ -x "$HOOK_DIR/$TARGET" ] || { cat >/dev/null; exit 0; }

INPUT=$(cat)

NORMALIZED=$(printf '%s' "$INPUT" | jq -c '{
  session_id: (.conversation_id // .session_id // "unknown"),
  prompt: (.prompt // ""),
  transcript_path: (.transcript_path // ""),
  cwd: (.cwd // (.workspace_roots[0]? // "")),
  message: (.message // .agent_message // "")
}' 2>/dev/null)

# Fail-open: if jq/normalization failed, pass the raw payload through — the
# target scripts already default every field with `// "unknown"` / `// ""`.
PAYLOAD="${NORMALIZED:-$INPUT}"

if [ "$TARGET" = "abbr-inject.sh" ]; then
  RAW_OUT=$(printf '%s' "$PAYLOAD" | "$HOOK_DIR/$TARGET")
  printf '%s' "$RAW_OUT" | jq -c '
    if (.hookSpecificOutput.additionalContext // "") != ""
    then {additional_context: .hookSpecificOutput.additionalContext}
    else empty end
  ' 2>/dev/null
  exit 0
fi

printf '%s' "$PAYLOAD" | "$HOOK_DIR/$TARGET" >/dev/null 2>&1
exit 0
