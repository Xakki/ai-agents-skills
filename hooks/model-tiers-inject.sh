#!/usr/bin/env bash
# SessionStart hook: inject resolved model tier slugs (cheap / standard / judgment)
# into context from AI_MODEL_* env + plugin defaults.env.
#
# Reads JSON on stdin (SessionStart payload); ignored. Always exits 0 — must
# never block session start. Emits additionalContext via hookSpecificOutput.

set -uo pipefail

HOOK_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
DEFAULTS="$HOOK_DIR/../skills/model-tiers/defaults.env"

read_default() {
    local key="$1"
    [ -r "$DEFAULTS" ] || return 0
    local line val
    line=$(grep -E "^[[:space:]]*${key}=" "$DEFAULTS" 2>/dev/null | tail -1) || return 0
    val="${line#*=}"
    val="${val%%#*}"
    val="${val#"${val%%[![:space:]]*}"}"
    val="${val%"${val##*[![:space:]]}"}"
    printf '%s' "$val"
}

resolve_tier() {
    local key="$1"
    local from_env="${!key:-}"
    if [ -n "$from_env" ]; then
        printf '%s' "$from_env"
    else
        read_default "$key"
    fi
}

CHEAP=$(resolve_tier AI_MODEL_CHEAP)
STANDARD=$(resolve_tier AI_MODEL_STANDARD)
JUDGMENT=$(resolve_tier AI_MODEL_JUDGMENT)

RUNTIME="unknown"
if [ -n "${HERMES_PLUGIN_ROOT:-}" ]; then
    RUNTIME="hermes"
elif [ -n "${CURSOR_PLUGIN_ROOT:-}" ]; then
    RUNTIME="cursor"
elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
    RUNTIME="claude"
elif [ -n "${PLUGIN_ROOT:-}" ]; then
    RUNTIME="codex"
elif [ -n "${PRIME_AGENT_ROOT:-}" ]; then
    RUNTIME="prime-agent"
fi

CTX="## Model tiers (resolved for this session)
runtime = ${RUNTIME}
cheap = ${CHEAP}
standard = ${STANDARD}
judgment = ${JUDGMENT}
Rule: pass these slugs as model: on every Agent/Task call. Skills name tiers (cheap|standard|judgment) only — never hardcode vendor model names."

printf '%s' "$CTX" \
    | jq -Rs '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:.}}' \
    2>/dev/null || exit 0

exit 0
