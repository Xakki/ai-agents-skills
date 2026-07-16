#!/usr/bin/env bash
# SessionStart hook: inject the abbreviations policy + dictionary into context so
# they are ALWAYS present from turn 1 — naming, comment style, and identifier
# recognition all build on them, and we don't want a lazy-load round-trip to get
# them. Single source of truth: the plugin's own SKILL.md (policy/disambiguation)
# + dictionary.tsv (the list) — no copy in any CLAUDE.md. The optional personal
# capture buffer is appended too.
#
# Reads JSON on stdin (SessionStart payload); ignored. Always exits 0 — must
# never block session start. Emits additionalContext via hookSpecificOutput.

set -uo pipefail

HOOK_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
SKILL="$HOOK_DIR/../skills/abbreviations/SKILL.md"
DICT="$HOOK_DIR/../skills/abbreviations/dictionary.tsv"
LOCAL_BUF="${ABBR_LOCAL:-$HOME/.config/abbr/local.tsv}"

[ -r "$DICT" ] || exit 0

# SKILL.md body without the YAML frontmatter (its `description` is already
# always-on via the skill system — don't duplicate it).
POLICY=""
if [ -r "$SKILL" ]; then
    POLICY=$(awk '/^---$/{fm++; next} fm>=2{print}' "$SKILL")
fi

# tab -> " = "; one entry per line (unambiguous vs comma-join for "a / b" forms)
DICT_BODY=$(sed -e 's/\t/ = /' "$DICT")

if [ -r "$LOCAL_BUF" ]; then
    EXTRA=$(grep -v '^[[:space:]]*#' "$LOCAL_BUF" 2>/dev/null \
        | grep -v '^[[:space:]]*$' \
        | sed -e 's/\t/ = /' || true)
    [ -n "$EXTRA" ] && DICT_BODY="$DICT_BODY"$'\n'"$EXTRA"
fi

CTX="${POLICY}

## Dictionary (abbr = full)
$DICT_BODY"

printf '%s' "$CTX" \
    | jq -Rs '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:.}}' \
    2>/dev/null || exit 0

exit 0
