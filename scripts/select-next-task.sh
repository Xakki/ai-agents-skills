#!/usr/bin/env bash
# Select the next runnable task from todo/.
# A card is BLOCKED if it contains a "depends on / blocked by" line referencing
# a task that is currently parked (has an entry in PARKED_DIR).
#
# Args: <REPO> <PARKED_DIR> [<JUST_FINISHED_NAME>]
# Prints: basename of next eligible card, or "none"
set -uo pipefail

REPO="$1"
PARKED_DIR="$2"
JUST_FINISHED="${3:-}"

LC_COLLATE=C

# 1. Glob todo cards in lex order (nullglob so empty dir gives zero elements).
shopt -s nullglob
TODO_CARDS=( "${REPO}"/.claude/kanban/todo/*.md )
shopt -u nullglob

if [ "${#TODO_CARDS[@]}" -eq 0 ]; then
    echo "none"
    exit 0
fi

# 2. Build space-separated list of parked task IDs from filenames in PARKED_DIR.
#    ID = leading ^[A-Za-z]+-[0-9]+ token; falls back to the whole basename.
PARKED_IDS=""
if [ -d "$PARKED_DIR" ]; then
    shopt -s nullglob
    for f in "${PARKED_DIR}"/*; do
        [ -f "$f" ] || continue
        name="$(basename "$f")"
        id="$(printf '%s' "$name" | grep -oE '^[A-Za-z]+-[0-9]+' || printf '%s' "$name")"
        PARKED_IDS="${PARKED_IDS} ${id}"
    done
    shopt -u nullglob
fi

# Returns 0 (true = blocked) if the card references any parked ID on a
# depends-on / blocked-by line.
# Over-block limitation: any card that BOTH contains a dependency keyword AND
# mentions the parked ID anywhere (even in a "Related work" section) is treated
# as blocked. False positives are possible but safe — the card is skipped for
# this chain link and will be eligible again once the parked task is resumed.
is_blocked() {
    local card="$1" id
    [ -z "$PARKED_IDS" ] && return 1
    for id in $PARKED_IDS; do
        if grep -iqE "(depends on|blocked by|зависит от|блокируется)" "$card" 2>/dev/null \
           && grep -qF "$id" "$card" 2>/dev/null; then
            return 0
        fi
    done
    return 1
}

# Extract the leading ID token from a card basename (e.g. K-025 from K-025-foo.md).
card_id() {
    local name
    name="$(basename "$1" .md)"
    printf '%s' "$name" | grep -oE '^[A-Za-z]+-[0-9]+' || printf '%s' "$name"
}

FINISHED_ID=""
if [ -n "$JUST_FINISHED" ]; then
    FINISHED_ID="$(printf '%s' "$JUST_FINISHED" | grep -oE '^[A-Za-z]+-[0-9]+' || printf '%s' "$JUST_FINISHED")"
fi

# 3. Walk cards in lex order; find first eligible related card and first eligible
#    card overall. Related = shares ID prefix with JUST_FINISHED, or mentions it.
RELATED=""
FIRST_ELIGIBLE=""
for card in "${TODO_CARDS[@]}"; do
    is_blocked "$card" && continue
    name="$(basename "$card")"
    [ -z "$FIRST_ELIGIBLE" ] && FIRST_ELIGIBLE="$name"
    if [ -n "$FINISHED_ID" ] && [ -z "$RELATED" ]; then
        cid="$(card_id "$card")"
        if [ "$cid" = "$FINISHED_ID" ] || grep -qF "$FINISHED_ID" "$card" 2>/dev/null; then
            RELATED="$name"
        fi
    fi
done

# 4. Prefer related-first; else lex-smallest eligible; else none.
if [ -n "$RELATED" ]; then
    echo "$RELATED"
elif [ -n "$FIRST_ELIGIBLE" ]; then
    echo "$FIRST_ELIGIBLE"
else
    echo "none"
fi
