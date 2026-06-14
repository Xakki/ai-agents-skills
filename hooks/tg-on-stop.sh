#!/usr/bin/env bash
# Stop hook: schedule a delayed Telegram "task finished" notification.
# Cancellation is filesystem-based: if the payload file is removed before sleep
# wakes (e.g. UserPromptSubmit fired), nothing is sent.
#
# Reads JSON on stdin: { session_id, transcript_path, cwd, ... }
# Always exits 0 — must not block session lifecycle.

set -uo pipefail

HOOK_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# shellcheck source=../skills/tg-notify/runtime.sh
source "$HOOK_DIR/../skills/tg-notify/runtime.sh"

STATE_DIR="$TG_STATE_DIR"
PENDING_DIR="$TG_PENDING_DIR"
TG="$TG_SENDER"
LOG_FILE="$TG_LOG_FILE"

DELIVERY_DELAY="${TG_NOTIFY_STOP_DELAY:-600}"       # 10 min cancel window
DEBOUNCE="${TG_NOTIFY_STOP_DEBOUNCE:-300}"         # 5 min between Stop schedules
STOP_THRESHOLD="${TG_NOTIFY_STOP_THRESHOLD:-1200}" # 20 min: min task duration to schedule notify

[[ -x "$TG" ]] || exit 0
mkdir -p "$STATE_DIR" "$PENDING_DIR" 2>/dev/null || exit 0

log() { printf '%s\t[on-stop]\t%s\n' "$(date -Iseconds)" "$*" >> "$LOG_FILE" 2>/dev/null || true; }

INPUT=$(cat)
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // ""' 2>/dev/null)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null)
[[ -n "$CWD" ]] || CWD="$PWD"

START_FILE="$STATE_DIR/$SESSION_ID.start"
started_at=0
prompt=""
if [[ -f "$START_FILE" ]]; then
    started_at=$(jq -r '.started_at // 0' "$START_FILE" 2>/dev/null)
    prompt=$(jq -r '.prompt // ""' "$START_FILE" 2>/dev/null)
fi
NOW=$(date +%s)
[[ "$started_at" =~ ^[0-9]+$ ]] || started_at=0
DUR=0
(( started_at > 0 )) && DUR=$(( NOW - started_at ))

# Skip short tasks — user is still at the terminal
if (( DUR > 0 && DUR < STOP_THRESHOLD )); then
    log "stop dur=${DUR}s < threshold=${STOP_THRESHOLD}s, skip"
    exit 0
fi

# Debounce: don't schedule again if we just did
LAST_FILE="$STATE_DIR/$SESSION_ID.last_stop"
if [[ -f "$LAST_FILE" ]]; then
    LAST=$(cat "$LAST_FILE" 2>/dev/null || echo 0)
    if (( NOW - LAST < DEBOUNCE )); then
        log "stop debounced (last $((NOW-LAST))s ago), skip"
        exit 0
    fi
fi
printf '%s' "$NOW" > "$LAST_FILE" 2>/dev/null || true

# Cancel any pending permission/idle payloads (turn is over — replace with stop notice)
if [[ -d "$PENDING_DIR/$SESSION_ID" ]]; then
    rm -f "$PENDING_DIR/$SESSION_ID"/*.payload 2>/dev/null
fi

# Mark session as stopped so post-Stop Notification idle events don't schedule duplicates
touch "$STATE_DIR/$SESSION_ID.stopped" 2>/dev/null || true

# ---- build body ----
if (( DUR > 0 )); then
    DUR_FMT=$(printf '%dm %02ds' $((DUR/60)) $((DUR%60)))
else
    DUR_FMT="?"
fi
PROMPT_TRIM="${prompt:-}"

LAST_TEXT=""
if [[ -n "$TRANSCRIPT" && -f "$TRANSCRIPT" ]]; then
    # Take the LAST assistant message that actually has text (skip tool_use-only entries)
    LAST_TEXT=$(jq -rs '
        [.[] | select(.type == "assistant")
             | (.message.content // []) | map(select(.type == "text") | .text) | join("\n")]
        | map(select(. != "")) | last // ""
    ' "$TRANSCRIPT" 2>/dev/null)
    log "stop last_text_len=${#LAST_TEXT}"
fi

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

BODY_RAW=""
BODY_RAW+="Длительность: $DUR_FMT"$'\n'
BODY_RAW+="Сессия: ${SESSION_ID:0:8}"$'\n'
[[ -n "$PROMPT_TRIM" ]] && BODY_RAW+="Запрос: $PROMPT_TRIM"$'\n'
if [[ -n "$LAST_TEXT" ]]; then
    BODY_RAW+=$'\n'"Ответ: "$'\n'"$LAST_TEXT"$'\n'
fi

BODY=$(truncate_body "$BODY_RAW")

source "$TG_SKILL_DIR/context-header.sh"
CTX=$(build_context_header "$CWD")
TITLE_LINE="✅ Задача завершена (${DUR_FMT})"
[[ -n "$CTX" ]] && TITLE="$CTX"$'\n'"$TITLE_LINE" || TITLE="$TITLE_LINE"

# ---- schedule delayed delivery ----
mkdir -p "$PENDING_DIR/$SESSION_ID" 2>/dev/null || exit 0
PAYLOAD="$PENDING_DIR/$SESSION_ID/$(date +%s%N).stop.payload"
printf '%s' "$BODY" > "$PAYLOAD" || exit 0
chmod 600 "$PAYLOAD" 2>/dev/null || true

log "stop scheduled, payload=$PAYLOAD delay=${DELIVERY_DELAY}s"

setsid bash -c "
    sleep $DELIVERY_DELAY
    if [[ -f '$PAYLOAD' ]]; then
        '$TG' -q -t $(printf '%q' "$TITLE") < '$PAYLOAD' \
            && printf '%s\t[on-stop]\tdelivered %s\n' \"\$(date -Iseconds)\" '$PAYLOAD' >> '$LOG_FILE' 2>/dev/null \
            || printf '%s\t[on-stop]\tdelivery FAILED %s\n' \"\$(date -Iseconds)\" '$PAYLOAD' >> '$LOG_FILE' 2>/dev/null
        rm -f '$PAYLOAD'
        rmdir '$PENDING_DIR/$SESSION_ID' 2>/dev/null || true
    else
        printf '%s\t[on-stop]\tcancelled %s\n' \"\$(date -Iseconds)\" '$PAYLOAD' >> '$LOG_FILE' 2>/dev/null
    fi
" </dev/null >/dev/null 2>&1 &
disown

exit 0
