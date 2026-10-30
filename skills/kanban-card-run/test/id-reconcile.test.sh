#!/usr/bin/env bash
# id-reconcile.test.sh — counter reconcile when the lock file is behind
# existing cards on disk (seed K-005, empty lock -> next is K-006), and the
# padding width follows the highest existing card's width.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KID="$HERE/../scripts/kanban-id.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
git_c() { git -c user.email=t@t -c user.name=t -c init.defaultBranch=main "$@"; }

REPO="$TMP/myrepo"
mkdir -p "$REPO/.claude/kanban/todo"
git_c -C "$REPO" init -q
: > "$REPO/.claude/kanban/todo/K-005-existing-card.md"
export KANBAN_PREFIX_REGISTRY="$TMP/registry.tsv"

# no lock file yet at all
[ -f "$REPO/.claude/kanban.lock" ] && { echo "FAIL: lock file should not pre-exist"; exit 1; }

ID="$(bash "$KID" --repo "$REPO" next K)"
[ "$ID" = "K-006" ] || { echo "FAIL: expected K-006, got $ID"; exit 1; }

# now seed a wider card and re-check padding follows the widest existing card
: > "$REPO/.claude/kanban/todo/K-00099-wide-card.md"
ID2="$(bash "$KID" --repo "$REPO" peek K)"
[ "$ID2" = "K-00099" ] || { echo "FAIL: expected peek K-00099 (5-digit width), got $ID2"; exit 1; }

echo "PASS id-reconcile"
