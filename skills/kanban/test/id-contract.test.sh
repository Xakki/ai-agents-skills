#!/usr/bin/env bash
# id-contract.test.sh — preserve exact ID tokens and scan duplicate IDs in every stage.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../scripts/kanban-lib.sh"
KLINT="$HERE/../scripts/kanban-lint.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1" >&2; exit 1; }
write_valid_card() {
  local path="$1" title="$2"
  printf '### %s\n**Criticality:** High\n**TAGS:** feature\n**Description:** test\n**Problem:** test\n**Impact:** test\n**Recommendation:** test\n**Acceptance Criteria:**\n- test\n' "$title" > "$path"
}

[ "$(kanban::extract_id 'K-094a-provider-browser-render')" = "K-094a" ] \
  || fail "letter-suffixed ID K-094a was truncated"
[ "$(kanban::extract_id 'K-094b-browser-resource-capture')" = "K-094b" ] \
  || fail "letter-suffixed ID K-094b was truncated"
[ "$(kanban::extract_id 'EPIC-042-03-third-child')" = "EPIC-042-03" ] \
  || fail "epic child ID parsing changed"
[ "$(kanban::card_prefix 'css-grid-feature')" = "" ] \
  || fail "a hyphenated slug was treated as a card prefix"
[ "$(kanban::card_prefix 'K-094a-provider-browser-render')" = "K" ] \
  || fail "numeric ID prefix was not recognized"

REPO="$TMP/id-board"
mkdir -p "$REPO/.agents/kanban/todo" "$REPO/.agents/kanban/done" \
  "$REPO/.agents/kanban/freeze" "$REPO/.agents/kanban/closed"
printf 'prefix=K\nK=99\n' > "$REPO/.agents/kanban.lock"
: > "$REPO/.agents/kanban/todo/css-grid-feature.md"
: > "$REPO/.agents/kanban/todo/K-001-alpha-suffix.md"
: > "$REPO/.agents/kanban/todo/K-094a-provider-browser-render.md"
: > "$REPO/.agents/kanban/todo/K-094b-browser-resource-capture.md"
PREFIXES="$(kanban::prefix_candidates_report "$REPO" | cut -f3 | sort -u)"
[ "$PREFIXES" = "K" ] || fail "prefix candidates included a slug token: $PREFIXES"

REPO_SUFFIX="$TMP/id-suffix-board"
mkdir -p "$REPO_SUFFIX/.agents/kanban/todo"
printf 'prefix=K\nK=94\n' > "$REPO_SUFFIX/.agents/kanban.lock"
write_valid_card "$REPO_SUFFIX/.agents/kanban/todo/K-094a-render.md" "Render a"
write_valid_card "$REPO_SUFFIX/.agents/kanban/todo/K-094b-capture.md" "Capture b"
set +e
OUT="$(bash "$KLINT" --repo "$REPO_SUFFIX" 2>&1)"
RC=$?
set -e
[[ "$RC" -eq 0 ]] || fail "lint rejected letter-suffixed IDs (exit $RC): $OUT"
if printf '%s\n' "$OUT" | grep -Eq '^(ERROR|WARN)'; then
  fail "lint rejected distinct letter-suffixed IDs: $OUT"
fi

: > "$REPO/.agents/kanban/todo/K-010-active-done-copy.md"
: > "$REPO/.agents/kanban/done/K-010-archived-copy.md"
: > "$REPO/.agents/kanban/todo/K-011-active-freeze-copy.md"
: > "$REPO/.agents/kanban/freeze/K-011-parked-copy.md"
: > "$REPO/.agents/kanban/todo/K-012-active-closed-copy.md"
: > "$REPO/.agents/kanban/closed/K-012-cancelled-copy.md"
set +e
OUT="$(bash "$KLINT" --repo "$REPO" 2>&1)"
RC=$?
set -e
[ "$RC" -eq 2 ] || fail "expected lint exit 2 for duplicate IDs, got $RC"
for id in K-010 K-011 K-012; do
  printf '%s\n' "$OUT" | grep -q "duplicate card ID '$id'" \
    || fail "duplicate ID $id was not found across all stages"
done

if printf '%s\n' "$OUT" | grep -q "duplicate card ID 'K-094'"; then
  fail "distinct IDs K-094a and K-094b collided"
fi

echo "PASS id-contract"
