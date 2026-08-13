#!/usr/bin/env bash
# status.test.sh — empty board prints "no cards"; populated board groups an
# epic's subtasks under it and marks the epic.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KNEW="$HERE/../scripts/kanban-new.sh"
KSTATUS="$HERE/../scripts/kanban-status.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
git_c() { git -c user.email=t@t -c user.name=t -c init.defaultBranch=main "$@"; }

REPO="$TMP/myrepo"
mkdir -p "$REPO"; git_c -C "$REPO" init -q
export KANBAN_PREFIX_REGISTRY="$TMP/registry.tsv"

OUT="$(bash "$KSTATUS" --repo "$REPO")"
[ "$OUT" = "no cards" ] || { echo "FAIL: expected 'no cards' on an empty board, got: $OUT"; exit 1; }

bash "$KNEW" --repo "$REPO" --title "Parent epic" --stage todo --prefix K --epic >/dev/null
bash "$KNEW" --repo "$REPO" --title "First subtask" --stage todo --sub EPIC-001 >/dev/null

OUT2="$(bash "$KSTATUS" --repo "$REPO")"
echo "$OUT2" | grep -q '^todo (2)$' || { echo "FAIL: expected todo (2) header"; echo "$OUT2"; exit 1; }
echo "$OUT2" | grep -q '\[epic\]' || { echo "FAIL: epic marker missing"; echo "$OUT2"; exit 1; }
echo "$OUT2" | grep -q '^    EPIC-001-01  First subtask$' || { echo "FAIL: subtask not indented under epic"; echo "$OUT2"; exit 1; }

echo "PASS status"
