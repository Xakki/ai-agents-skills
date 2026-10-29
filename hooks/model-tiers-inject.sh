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

RUNTIME="unknown"
if [ -n "${HERMES_PLUGIN_ROOT:-}" ]; then
    RUNTIME="hermes"
elif [ -n "${CURSOR_PLUGIN_ROOT:-}" ]; then
    RUNTIME="cursor"
elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
    RUNTIME="claude"
elif [ -n "${PRIME_AGENT_ROOT:-}" ]; then
    RUNTIME="prime-agent"
elif [ -n "${PLUGIN_ROOT:-}" ]; then
    RUNTIME="codex"
fi

resolve_tier() {
    local key="$1" value
    value="${!key:-}"
    # Shipped aliases are Claude-specific; other runtimes must not inherit
    # a vendor's model selectors unless explicitly configured for that runtime.
    # A generic plugin marker may come from a second active agent; do not infer
    # Claude defaults from overlapping process environments.
    if [ -z "$value" ] && [ "$RUNTIME" = claude ] && [ -z "${PLUGIN_ROOT:-}" ]; then
        value="$(read_default "$key")"
    fi
    # Keep configuration values from injecting extra instructions or lines.
    if [[ "$value" =~ ^[A-Za-z0-9._:/@+-]+$ ]]; then
        printf '%s' "$value"
    else
        printf 'unconfigured'
    fi
}

CHEAP=$(resolve_tier AI_MODEL_CHEAP)
STANDARD=$(resolve_tier AI_MODEL_STANDARD)
JUDGMENT=$(resolve_tier AI_MODEL_JUDGMENT)

CTX="## Model tiers (resolved for this session)
runtime = ${RUNTIME}
cheap = ${CHEAP}
standard = ${STANDARD}
judgment = ${JUDGMENT}
Treat these as optional configuration hints. Preserve the runtime's inherited model and user instructions unless a supported, authorized model override is needed; verify that a selector is valid for the active runtime. Never pass an unconfigured tier as a model."

printf '%s' "$CTX" \
    | jq -Rs '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:.}}' \
    2>/dev/null || exit 0

exit 0
