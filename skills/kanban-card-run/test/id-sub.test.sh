#!/usr/bin/env bash
# id-sub.test.sh — subtask numbering starts at 01, increments, and errors
# when the epic itself doesn't exist on the board.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KID="$HERE/../scripts/kanban-id.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
git_c() { git -c user.email=t@t -c user.name=t -c init.defaultBranch=main "$@"; }

REPO="$TMP/myrepo"
mkdir -p "$REPO/.claude/kanban/todo"
git_c -C "$REPO" init -q
export KANBAN_PREFIX_REGISTRY="$TMP/registry.tsv"

# sub of a non-existent epic errors clearly
set +e
OUT="$(bash "$KID" --repo "$REPO" sub K-999 2>&1)"; rc=$?
set -e
[ "$rc" -eq 2 ] || { echo "FAIL: expected exit 2 (validation/not-found) for missing epic, got $rc"; exit 1; }
printf '%s' "$OUT" | grep -qi "non-existent\|no card found" || { echo "FAIL: error message unclear: $OUT"; exit 1; }

# seed the epic card
: > "$REPO/.claude/kanban/todo/K-042-billing-epic.md"

S1="$(bash "$KID" --repo "$REPO" sub K-042)"
[ "$S1" = "K-042-01" ] || { echo "FAIL: expected K-042-01, got $S1"; exit 1; }

# create the subtask card so the next sub call sees it and increments
: > "$REPO/.claude/kanban/todo/K-042-01-db-schema.md"
S2="$(bash "$KID" --repo "$REPO" sub K-042)"
[ "$S2" = "K-042-02" ] || { echo "FAIL: expected K-042-02, got $S2"; exit 1; }

echo "PASS id-sub"
