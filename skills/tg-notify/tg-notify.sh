#!/usr/bin/env bash
# tg-notify.sh — send a notification with a report to Telegram.
#
# Usage:
#   tg-notify.sh -t "Title" -m "Body text"             # send title + body
#   tg-notify.sh -t "Title" -f /path/to/report.md       # body from file
#   echo "body" | tg-notify.sh -t "Title"               # body from stdin
#
# Optional flags:
#   -p plain|html|markdown   parse mode (default: html)
#   -c CHAT_ID               override chat id (destination)
#   -T THREAD_ID             override topic/thread id
#   -s STATUS                ok | fail | warn | info (decorates the title)
#   -M MENTION               override mention (e.g. "@user"); empty string disables
#   -q                       quiet (no stdout on success)
#
# Credentials & destination — from the environment (see .env.example):
#   TELEGRAM_BOT_TOKEN   bot token (required)
#   TELEGRAM_CHAT_ID     destination (required):
#                          • DM      — numeric user id        (e.g. 123456789)
#                          • group   — supergroup id          (e.g. -1001234567890)
#                          • channel — channel id or @name    (e.g. @my_channel)
#   TELEGRAM_THREAD_ID   forum topic id (optional; sent only when non-empty)
#   TELEGRAM_MENTION     prepended to every message (optional; e.g. @user)
#
# Env vars may be exported in the shell OR placed in a creds file (chmod 600) at
#   $TG_NOTIFY_ENV  (default: $XDG_CONFIG_HOME/tg-notify/.env, i.e. ~/.config/tg-notify/.env)
# Real exported variables take precedence over the file.
#
# Logs/failed payloads live under the writable runtime home (see runtime.sh):
#   $TG_NOTIFY_HOME (default: $CLAUDE_PLUGIN_DATA or ~/.local/state/tg-notify)
#
# Telegram limits: 4096 chars/message. Long bodies are split, keeping the title
# only on the first message. Each chunk is retried up to 3 times with backoff.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# shellcheck source=runtime.sh
source "$SCRIPT_DIR/runtime.sh"

ENV_FILE="$TG_ENV_FILE"
if [[ -f "$ENV_FILE" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
fi

TITLE=""
BODY=""
BODY_FILE=""
PARSE_MODE="HTML"
STATUS=""
QUIET=0
CHAT_ID="${TELEGRAM_CHAT_ID:-}"
THREAD_ID="${TELEGRAM_THREAD_ID:-}"
TOKEN="${TELEGRAM_BOT_TOKEN:-}"
MENTION="${TELEGRAM_MENTION-}"

LOG_FILE="${TG_NOTIFY_LOG:-$TG_LOG_FILE}"
FAILED_DIR="${TG_NOTIFY_FAILED_DIR:-$TG_FAILED_DIR}"
MAX_ATTEMPTS="${TG_NOTIFY_MAX_ATTEMPTS:-3}"

mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true

while getopts ":t:m:f:p:c:T:s:M:q" opt; do
    case "$opt" in
        t) TITLE="$OPTARG" ;;
        m) BODY="$OPTARG" ;;
        f) BODY_FILE="$OPTARG" ;;
        p)
            case "$OPTARG" in
                plain) PARSE_MODE="" ;;
                html|HTML) PARSE_MODE="HTML" ;;
                md|markdown|Markdown|MARKDOWN) PARSE_MODE="MarkdownV2" ;;
                *) echo "tg-notify: unknown parse mode '$OPTARG'" >&2; exit 2 ;;
            esac
            ;;
        c) CHAT_ID="$OPTARG" ;;
        T) THREAD_ID="$OPTARG" ;;
        s) STATUS="$OPTARG" ;;
        M) MENTION="$OPTARG" ;;
        q) QUIET=1 ;;
        :) echo "tg-notify: option -$OPTARG requires an argument" >&2; exit 2 ;;
        \?) echo "tg-notify: unknown option -$OPTARG" >&2; exit 2 ;;
    esac
done

if [[ -z "$TOKEN" || -z "$CHAT_ID" ]]; then
    echo "tg-notify: TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID must be set (env or $ENV_FILE)" >&2
    exit 2
fi

if [[ -n "$BODY_FILE" ]]; then
    BODY="$(cat -- "$BODY_FILE")"
elif [[ -z "$BODY" ]] && [[ ! -t 0 ]]; then
    BODY="$(cat)"
fi

case "$STATUS" in
    ok)   PREFIX="✅ " ;;
    fail) PREFIX="❌ " ;;
    warn) PREFIX="⚠️ " ;;
    info) PREFIX="ℹ️ " ;;
    "")   PREFIX="" ;;
    *)    PREFIX="$STATUS " ;;
esac

html_escape() {
    sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

if [[ "$PARSE_MODE" == "HTML" ]]; then
    HEADER=""
    if [[ -n "$MENTION" ]]; then
        HEADER="$(printf '%s' "$MENTION" | html_escape)"
    fi
    if [[ -n "$TITLE" ]]; then
        title_html="<b>$(printf '%s' "$PREFIX$TITLE" | html_escape)</b>"
        if [[ -n "$HEADER" ]]; then
            HEADER="$HEADER"$'\n'"$title_html"
        else
            HEADER="$title_html"
        fi
    fi
    BODY_FORMATTED=""
    if [[ -n "$BODY" ]]; then
        BODY_FORMATTED="<pre>$(printf '%s' "$BODY" | html_escape)</pre>"
    fi
    if [[ -n "$HEADER" && -n "$BODY_FORMATTED" ]]; then
        FULL_TEXT="$HEADER"$'\n'"$BODY_FORMATTED"
    else
        FULL_TEXT="${HEADER}${BODY_FORMATTED}"
    fi
else
    PLAIN_HEADER=""
    if [[ -n "$MENTION" ]]; then
        PLAIN_HEADER="$MENTION"
    fi
    if [[ -n "$TITLE" ]]; then
        if [[ -n "$PLAIN_HEADER" ]]; then
            PLAIN_HEADER="$PLAIN_HEADER"$'\n'"$PREFIX$TITLE"
        else
            PLAIN_HEADER="$PREFIX$TITLE"
        fi
    fi
    if [[ -n "$PLAIN_HEADER" && -n "$BODY" ]]; then
        FULL_TEXT="$PLAIN_HEADER"$'\n\n'"$BODY"
    else
        FULL_TEXT="${PLAIN_HEADER}${BODY}"
    fi
fi

if [[ -z "$FULL_TEXT" ]]; then
    echo "tg-notify: nothing to send (provide -t/-m/-f or stdin)" >&2
    exit 2
fi

API="https://api.telegram.org/bot${TOKEN}/sendMessage"

log() {
    local line
    line="$(date -Iseconds 2>/dev/null || date)"$'\t'"$*"
    printf '%s\n' "$line" >> "$LOG_FILE" 2>/dev/null || true
}

save_failed() {
    local text="$1"
    mkdir -p "$FAILED_DIR" 2>/dev/null || { log "save_failed: cannot create $FAILED_DIR"; return 1; }
    local f="$FAILED_DIR/$(date -u +%Y%m%dT%H%M%SZ)-$$-${RANDOM}.txt"
    if printf '%s' "$text" > "$f" 2>/dev/null; then
        chmod 600 "$f" 2>/dev/null || true
        log "save_failed: wrote $f (${#text} chars)"
        echo "tg-notify: payload saved to $f" >&2
        return 0
    fi
    log "save_failed: write to $f failed"
    return 1
}

send_chunk_once() {
    local text="$1"
    local args=(--silent --show-error --max-time 30
        --write-out '\n%{http_code}'
        --data-urlencode "chat_id=${CHAT_ID}"
        --data-urlencode "text=${text}"
        --data-urlencode "disable_web_page_preview=true")
    if [[ -n "$THREAD_ID" ]]; then
        args+=(--data-urlencode "message_thread_id=${THREAD_ID}")
    fi
    if [[ -n "$PARSE_MODE" ]]; then
        args+=(--data-urlencode "parse_mode=${PARSE_MODE}")
    fi
    local raw curl_rc=0
    raw=$(curl "${args[@]}" "$API" 2>&1) || curl_rc=$?
    local http_code="${raw##*$'\n'}"
    local response="${raw%$'\n'*}"
    if (( curl_rc != 0 )); then
        SEND_ERR="curl rc=$curl_rc: $response"
        return 1
    fi
    if ! grep -q '"ok":true' <<<"$response"; then
        SEND_ERR="http=$http_code response=$response"
        return 1
    fi
    return 0
}

send_chunk() {
    local text="$1"
    local attempt
    SEND_ERR=""
    for (( attempt=1; attempt<=MAX_ATTEMPTS; attempt++ )); do
        if send_chunk_once "$text"; then
            if [[ "$QUIET" -eq 0 ]]; then
                echo "tg-notify: sent (${#text} chars$( ((attempt>1)) && printf ', attempt %d' "$attempt"))"
            fi
            return 0
        fi
        log "send attempt $attempt/$MAX_ATTEMPTS failed: $SEND_ERR"
        if (( attempt < MAX_ATTEMPTS )); then
            sleep $(( attempt * 2 ))
        fi
    done
    echo "tg-notify: send failed after $MAX_ATTEMPTS attempts: $SEND_ERR" >&2
    save_failed "$text" || true
    return 1
}

# split into <=4000-char chunks (HTML safety margin)
LIMIT=4000
FAILED_CHUNKS=0
if (( ${#FULL_TEXT} <= LIMIT )); then
    send_chunk "$FULL_TEXT" || FAILED_CHUNKS=$((FAILED_CHUNKS + 1))
else
    if [[ "$PARSE_MODE" == "HTML" && ( -n "$TITLE" || -n "$MENTION" ) ]]; then
        first_chunk=""
        if [[ -n "$MENTION" ]]; then
            first_chunk="$(printf '%s' "$MENTION" | html_escape)"
        fi
        if [[ -n "$TITLE" ]]; then
            title_html="<b>$(printf '%s' "$PREFIX$TITLE" | html_escape)</b>"
            if [[ -n "$first_chunk" ]]; then
                first_chunk="$first_chunk"$'\n'"$title_html"
            else
                first_chunk="$title_html"
            fi
        fi
        send_chunk "$first_chunk" || FAILED_CHUNKS=$((FAILED_CHUNKS + 1))
        rest="$BODY"
    else
        rest="$FULL_TEXT"
    fi
    while [[ -n "$rest" ]]; do
        chunk="${rest:0:$LIMIT}"
        rest="${rest:$LIMIT}"
        if [[ "$PARSE_MODE" == "HTML" ]]; then
            send_chunk "<pre>$(printf '%s' "$chunk" | html_escape)</pre>" || FAILED_CHUNKS=$((FAILED_CHUNKS + 1))
        else
            send_chunk "$chunk" || FAILED_CHUNKS=$((FAILED_CHUNKS + 1))
        fi
    done
fi

if (( FAILED_CHUNKS > 0 )); then
    log "run finished with $FAILED_CHUNKS undelivered chunk(s)"
    echo "tg-notify: $FAILED_CHUNKS chunk(s) undelivered; see $LOG_FILE and $FAILED_DIR" >&2
    exit 1
fi
