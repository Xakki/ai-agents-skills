#!/usr/bin/env bash
# context-header.sh — build the notification header line "tab | compose | dir".
# Sourced by the tg-notify hooks. All lookups fail soft to empty.
#
#   ctx=$(build_context_header "$CWD")   # "mytab | myproj | api" (empty parts dropped)
#
# tab     — byobu/tmux window name (#W), captured at call time from the inherited TMUX env.
# compose — COMPOSE_PROJECT_NAME from env, else grepped from "$cwd/.env" (NOT sourced).
# dir     — basename of cwd.

build_context_header() {
    local cwd="${1:-$PWD}" tab compose dir
    local -a parts=()

    tab=""
    if [[ -n "${TMUX:-}" && -n "${TMUX_PANE:-}" ]]; then
        tab=$(tmux display-message -p -t "$TMUX_PANE" '#W' 2>/dev/null)
    fi
    [[ -z "$tab" || "$tab" == "-" ]] && tab="${BYOBU_WINDOW_NAME:-}"
    [[ "$tab" == "-" ]] && tab=""
    [[ -n "$tab" ]] && parts+=("$tab")

    compose="${COMPOSE_PROJECT_NAME:-}"
    if [[ -z "$compose" && -f "$cwd/.env" ]]; then
        compose=$(grep -E '^[[:space:]]*COMPOSE_PROJECT_NAME=' "$cwd/.env" 2>/dev/null \
            | head -1 | cut -d= -f2- | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^["'\'']//' -e 's/["'\'']$//')
    fi
    [[ -n "$compose" ]] && parts+=("$compose")

    dir=$(basename "$cwd" 2>/dev/null)
    [[ -n "$dir" ]] && parts+=("$dir")

    local out="" p
    for p in "${parts[@]}"; do
        [[ -n "$out" ]] && out="$out | $p" || out="$p"
    done
    printf '%s' "$out"
}
