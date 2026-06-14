#!/usr/bin/env bash
# Notification hook: schedule a delayed Telegram "needs attention" notification
# for permission prompts and idle waits.
#
# Reads JSON on stdin: { session_id, transcript_path, message, cwd, ... }
# Always exits 0 — must not block.

set -uo pipefail

HOOK_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# shellcheck source=../skills/tg-notify/runtime.sh
source "$HOOK_DIR/../skills/tg-notify/runtime.sh"

STATE_DIR="$TG_STATE_DIR"
PENDING_DIR="$TG_PENDING_DIR"
TG="$TG_SENDER"
LOG_FILE="$TG_LOG_FILE"

# Thresholds (seconds since UserPromptSubmit) and delivery delay. Overridable via env.
PERM_THRESHOLD="${TG_NOTIFY_PERM_THRESHOLD:-1200}"   # 20 min
IDLE_THRESHOLD="${TG_NOTIFY_IDLE_THRESHOLD:-600}"    # 10 min
DELIVERY_DELAY="${TG_NOTIFY_DELAY:-300}"             # 5 min: cancel window
DEBOUNCE="${TG_NOTIFY_DEBOUNCE:-300}"                # 5 min between schedules

[[ -x "$TG" ]] || exit 0
mkdir -p "$STATE_DIR" "$PENDING_DIR" 2>/dev/null || exit 0

log() { printf '%s\t[on-notify]\t%s\n' "$(date -Iseconds)" "$*" >> "$LOG_FILE" 2>/dev/null || true; }

INPUT=$(cat)
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // ""' 2>/dev/null)
MESSAGE=$(printf '%s' "$INPUT" | jq -r '.message // ""' 2>/dev/null)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null)
[[ -n "$CWD" ]] || CWD="$PWD"

# Skip if session already Stopped — avoids duplicate idle notifications after Stop
if [[ -f "$STATE_DIR/$SESSION_ID.stopped" ]]; then
    log "session $SESSION_ID already stopped, skip"
    exit 0
fi

# Need a recorded start to compute duration
START_FILE="$STATE_DIR/$SESSION_ID.start"
[[ -f "$START_FILE" ]] || { log "no start file for $SESSION_ID, skip"; exit 0; }

started_at=$(jq -r '.started_at // 0' "$START_FILE" 2>/dev/null)
prompt=$(jq -r '.prompt // ""' "$START_FILE" 2>/dev/null)
NOW=$(date +%s)
[[ "$started_at" =~ ^[0-9]+$ ]] || { log "invalid started_at in $START_FILE, skip"; exit 0; }
DUR=$(( NOW - started_at ))

# Classify event
if [[ "$MESSAGE" == *permission* || "$MESSAGE" == *разрешени* ]]; then
    KIND="permission"
    THRESHOLD="$PERM_THRESHOLD"
    STATUS="warn"
    TITLE_PREFIX="🔐 Требуется разрешение"
else
    KIND="idle"
    THRESHOLD="$IDLE_THRESHOLD"
    STATUS="info"
    TITLE_PREFIX="⏰ Ожидает ввода"
fi

if (( DUR < THRESHOLD )); then
    log "kind=$KIND dur=${DUR}s < threshold=${THRESHOLD}s, skip"
    exit 0
fi

# Debounce: don't schedule again if we just did
LAST_FILE="$STATE_DIR/$SESSION_ID.last_scheduled"
if [[ -f "$LAST_FILE" ]]; then
    LAST=$(cat "$LAST_FILE" 2>/dev/null || echo 0)
    if (( NOW - LAST < DEBOUNCE )); then
        log "kind=$KIND debounced (last $((NOW-LAST))s ago), skip"
        exit 0
    fi
fi
printf '%s' "$NOW" > "$LAST_FILE" 2>/dev/null || true

# ---- build body ----
DUR_FMT=$(printf '%dm %02ds' $((DUR/60)) $((DUR%60)))

# Multibyte-aware truncation (bash ${var:0:n} is byte-based — would split UTF-8)
truncate_body() {
    python3 -c '
import sys
t = sys.argv[1]
# Body budget: tg-notify.sh splits the wrapped HTML at 4000 chars. Header
# (mention + title) + <pre></pre> wrapper ≈ 70 chars; leave slack for HTML
# escaping (<, >, & expand). 3800 fits one Telegram message in practice.
mx = 3800
if len(t) <= mx:
    sys.stdout.write(t)
else:
    cut = len(t) - mx
    suffix = f"\n\n... [{cut} симв. вырезано с конца]"
    keep = mx - len(suffix)
    sys.stdout.write(t[:keep] + suffix)
' "$1"
}

PROMPT_TRIM="${prompt:-}"

# Pull last assistant message text-only (drop tool_use/tool_result),
# and pending tool_uses for permission requests.
LAST_TEXT=""
PENDING_TOOLS=""
if [[ -n "$TRANSCRIPT" && -f "$TRANSCRIPT" ]]; then
    # Take the LAST assistant message that actually has text (skip tool_use-only entries)
    LAST_TEXT=$(jq -rs '
        [.[] | select(.type == "assistant")
             | (.message.content // []) | map(select(.type == "text") | .text) | join("\n")]
        | map(select(. != "")) | last // ""
    ' "$TRANSCRIPT" 2>/dev/null)

    if [[ "$KIND" == "permission" ]]; then
        PENDING_TOOLS=$(jq -rs '
            map(select(.type == "assistant")) | last // {}
            | .message.content[]? | select(.type == "tool_use")
            | "• \(.name): \(.input | tostring)"
        ' "$TRANSCRIPT" 2>/dev/null)
    fi
fi

BODY_RAW=""
BODY_RAW+="Длительность: $DUR_FMT (порог $((THRESHOLD/60)) мин)"$'\n'
BODY_RAW+="Сессия: ${SESSION_ID:0:8}"$'\n'
[[ -n "$PROMPT_TRIM" ]] && BODY_RAW+="Запрос: $PROMPT_TRIM"$'\n'
if [[ -n "$PENDING_TOOLS" ]]; then
    BODY_RAW+=$'\n'"Tool:"$'\n'"$PENDING_TOOLS"$'\n'
fi
if [[ -n "$LAST_TEXT" ]]; then
    BODY_RAW+=$'\n'"Ответ: "$'\n'"$LAST_TEXT"$'\n'
fi

BODY=$(truncate_body "$BODY_RAW")

source "$TG_SKILL_DIR/context-header.sh"
CTX=$(build_context_header "$CWD")
TITLE_LINE="$TITLE_PREFIX (${DUR_FMT})"
[[ -n "$CTX" ]] && TITLE="$CTX"$'\n'"$TITLE_LINE" || TITLE="$TITLE_LINE"

# ---- schedule delayed delivery ----
mkdir -p "$PENDING_DIR/$SESSION_ID" 2>/dev/null || exit 0
PAYLOAD="$PENDING_DIR/$SESSION_ID/$(date +%s%N).$KIND.payload"
printf '%s' "$BODY" > "$PAYLOAD" || exit 0
chmod 600 "$PAYLOAD" 2>/dev/null || true

log "kind=$KIND dur=${DUR}s scheduled, payload=$PAYLOAD delay=${DELIVERY_DELAY}s"

setsid bash -c "
    sleep $DELIVERY_DELAY
    if [[ -f '$PAYLOAD' ]]; then
        '$TG' -q -t $(printf '%q' "$TITLE") < '$PAYLOAD' \
            && printf '%s\t[on-notify]\tdelivered %s\n' \"\$(date -Iseconds)\" '$PAYLOAD' >> '$LOG_FILE' 2>/dev/null \
            || printf '%s\t[on-notify]\tdelivery FAILED %s\n' \"\$(date -Iseconds)\" '$PAYLOAD' >> '$LOG_FILE' 2>/dev/null
        rm -f '$PAYLOAD'
        rmdir '$PENDING_DIR/$SESSION_ID' 2>/dev/null || true
    else
        printf '%s\t[on-notify]\tcancelled %s\n' \"\$(date -Iseconds)\" '$PAYLOAD' >> '$LOG_FILE' 2>/dev/null
    fi
" </dev/null >/dev/null 2>&1 &
disown

exit 0
