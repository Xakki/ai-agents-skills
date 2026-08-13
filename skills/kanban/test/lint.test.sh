#!/usr/bin/env bash
# lint.test.sh — kanban-lint.sh catches a duplicate ID across stages and a
# card missing a required section.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KNEW="$HERE/../scripts/kanban-new.sh"
KLINT="$HERE/../scripts/kanban-lint.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
git_c() { git -c user.email=t@t -c user.name=t -c init.defaultBranch=main "$@"; }

# The board may itself live beneath an unrelated ancestor directory named done.
# Such active cards must not be treated as archived.
REPO="$TMP/done/myrepo"
mkdir -p "$REPO"; git_c -C "$REPO" init -q
export KANBAN_PREFIX_REGISTRY="$TMP/registry.tsv"

# a well-formed card should lint clean
bash "$KNEW" --repo "$REPO" --title "Well formed" --stage todo --prefix K >/dev/null
OUT="$(bash "$KLINT" --repo "$REPO")"
echo "$OUT" | grep -q '^ERROR' && { echo "FAIL: expected no errors on a well-formed card"; echo "$OUT"; exit 1; }

# Archived done cards are intentionally excluded from linting.
mkdir -p "$REPO/.claude/kanban/done"
cat > "$REPO/.claude/kanban/done/K-002-archived-broken.md" <<'EOF'
no title, no sections
EOF
OUT_DONE="$(bash "$KLINT" --repo "$REPO")"
echo "$OUT_DONE" | grep -q '^ERROR' && { echo "FAIL: expected done/ cards to be excluded from linting"; echo "$OUT_DONE"; exit 1; }
echo "$OUT_DONE" | grep -q '^kanban-lint: 1 card(s) checked' || { echo "FAIL: expected only active cards to be checked"; echo "$OUT_DONE"; exit 1; }
OUT_DONE_EXPLICIT="$(bash "$KLINT" --repo "$REPO" "$REPO/.claude/kanban/done/K-002-archived-broken.md")"
echo "$OUT_DONE_EXPLICIT" | grep -q '^ERROR' && { echo "FAIL: expected explicitly targeted done/ cards to be excluded from linting"; echo "$OUT_DONE_EXPLICIT"; exit 1; }
echo "$OUT_DONE_EXPLICIT" | grep -q '^kanban-lint: 0 card(s) checked' || { echo "FAIL: expected no explicitly targeted done/ cards to be checked"; echo "$OUT_DONE_EXPLICIT"; exit 1; }

# A bare basename must resolve the active card when an archived duplicate exists.
cp "$REPO/.claude/kanban/todo/K-001-well-formed.md" "$REPO/.claude/kanban/todo/K-003-shared-card.md"
cat > "$REPO/.claude/kanban/done/K-003-shared-card.md" <<'EOF'
no title, no sections
EOF
OUT_ACTIVE_REF="$(bash "$KLINT" --repo "$REPO" K-003-shared-card)"
echo "$OUT_ACTIVE_REF" | grep -q '^ERROR' && { echo "FAIL: expected bare reference to lint the active duplicate"; echo "$OUT_ACTIVE_REF"; exit 1; }
echo "$OUT_ACTIVE_REF" | grep -q '^kanban-lint: 1 card(s) checked' || { echo "FAIL: expected bare reference to check the active duplicate"; echo "$OUT_ACTIVE_REF"; exit 1; }
rm -f "$REPO/.claude/kanban/todo/K-003-shared-card.md" "$REPO/.claude/kanban/done/K-003-shared-card.md"

# duplicate ID across stages: copy the same card basename into two stage dirs
mkdir -p "$REPO/.claude/kanban/progress"
cp "$REPO/.claude/kanban/todo/K-001-well-formed.md" "$REPO/.claude/kanban/progress/K-001-well-formed.md"

# missing-section card: required sections stripped
mkdir -p "$REPO/.claude/kanban/grooming"
cat > "$REPO/.claude/kanban/grooming/K-002-broken-card.md" <<'EOF'
### Broken card

**Description:**
No TAGS, no Criticality, no Acceptance Criteria.
EOF

set +e
OUT2="$(bash "$KLINT" --repo "$REPO" 2>&1)"
rc=$?
set -e
[ "$rc" -eq 2 ] || { echo "FAIL: expected exit 2 (findings present) due to errors, got $rc"; echo "$OUT2"; exit 1; }
echo "$OUT2" | grep -q "duplicate card ID 'K-001'" || { echo "FAIL: duplicate-ID error not reported"; echo "$OUT2"; exit 1; }
echo "$OUT2" | grep -q "missing required section \*\*TAGS:\*\*" || { echo "FAIL: missing-section error not reported"; echo "$OUT2"; exit 1; }
echo "$OUT2" | grep -q "missing required section \*\*Criticality:\*\*" || { echo "FAIL: missing Criticality error not reported"; echo "$OUT2"; exit 1; }
echo "$OUT2" | grep -q "missing required section \*\*Problem:\*\*" || { echo "FAIL: missing Problem error not reported"; echo "$OUT2"; exit 1; }
echo "$OUT2" | grep -q "missing required section \*\*Impact:\*\*" || { echo "FAIL: missing Impact error not reported"; echo "$OUT2"; exit 1; }
echo "$OUT2" | grep -q "missing required section \*\*Recommendation:\*\*" || { echo "FAIL: missing Recommendation error not reported"; echo "$OUT2"; exit 1; }
echo "$OUT2" | grep -qF "K-002-broken-card.md: grooming/ card has no" || { echo "FAIL: expected grooming-missing-Open-questions warning"; echo "$OUT2"; exit 1; }

# counter drift: a prefix with cards on the board but NO lock counter entry
# at all (ctr=0, e.g. a legacy board that never went through kanban-id.sh)
# must NOT be reported as "drift" — only the "not registered" warning fires.
mkdir -p "$REPO/.claude/kanban/todo"
: > "$REPO/.claude/kanban/todo/Z-001-legacy-card.md"
OUT3="$(bash "$KLINT" --repo "$REPO" 2>&1 || true)"
echo "$OUT3" | grep -q "Z-001-legacy-card.md:.*counter drift" && { echo "FAIL: unexpected counter-drift noise for a prefix with no lock entry"; echo "$OUT3"; exit 1; }
echo "$OUT3" | grep -qF "Z-001-legacy-card.md: prefix 'Z' is not registered in the lock file" || { echo "FAIL: expected 'not registered' warning for Z"; echo "$OUT3"; exit 1; }
rm -f "$REPO/.claude/kanban/todo/Z-001-legacy-card.md"

# a genuine drift (card number ahead of a REAL recorded counter) still fires.
: > "$REPO/.claude/kanban/todo/K-999-drift-card.md"
OUT4="$(bash "$KLINT" --repo "$REPO" 2>&1 || true)"
echo "$OUT4" | grep -q "K-999-drift-card.md: card number 999 exceeds lock counter 1 for prefix 'K' (counter drift)" || { echo "FAIL: expected genuine counter-drift warning"; echo "$OUT4"; exit 1; }
rm -f "$REPO/.claude/kanban/todo/K-999-drift-card.md"

echo "PASS lint"
