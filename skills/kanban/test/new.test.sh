#!/usr/bin/env bash
# new.test.sh — kanban-new.sh filename/slug/template rendering and
# grooming-vs-todo Open-questions handling.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KNEW="$HERE/../scripts/kanban-new.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
git_c() { git -c user.email=t@t -c user.name=t -c init.defaultBranch=main "$@"; }

REPO="$TMP/myrepo"
mkdir -p "$REPO"; git_c -C "$REPO" init -q
export KANBAN_PREFIX_REGISTRY="$TMP/registry.tsv"

# --- todo card: slug sanitized, Open questions dropped ---------------------

PATH1="$(bash "$KNEW" --repo "$REPO" --title "My Cool Task!!" --stage todo --prefix K --crit Medium --tag bug-fix)"
[ -f "$PATH1" ] || { echo "FAIL: card not created: $PATH1"; exit 1; }
case "$(basename "$PATH1")" in
  K-001-my-cool-task.md) ;;
  *) echo "FAIL: unexpected filename: $(basename "$PATH1")"; exit 1 ;;
esac

grep -q '^### My Cool Task!!$' "$PATH1" || { echo "FAIL: title not rendered"; cat "$PATH1"; exit 1; }
grep -q '^\*\*Criticality:\*\* Medium$' "$PATH1" || { echo "FAIL: criticality not rendered"; exit 1; }
grep -q '^- bug-fix$' "$PATH1" || { echo "FAIL: tag not rendered"; exit 1; }
grep -q '\*\*Open questions:\*\*' "$PATH1" && { echo "FAIL: todo card must not contain Open questions"; exit 1; }
grep -q '\*\*Decisions:\*\*' "$PATH1" || { echo "FAIL: todo card should still keep Decisions"; exit 1; }

# --- grooming card: Open questions kept -------------------------------------

PATH2="$(bash "$KNEW" --repo "$REPO" --title "Ambiguous scope" --stage grooming --prefix K)"
grep -q '\*\*Open questions:\*\*' "$PATH2" || { echo "FAIL: grooming card should keep Open questions"; exit 1; }
grep -q '^\*\*Criticality:\*\* \[Blocking | High | Medium | Minor\]$' "$PATH2" || { echo "FAIL: unfilled criticality placeholder should survive"; exit 1; }

# --- epic card gets Subtasks / Integration checklist ------------------------

PATH3="$(bash "$KNEW" --repo "$REPO" --title "Big migration" --stage todo --prefix K --epic)"
grep -q '^\*\*Subtasks:\*\*$' "$PATH3" || { echo "FAIL: epic card missing Subtasks section"; exit 1; }
grep -q '^\*\*Integration checklist:\*\*$' "$PATH3" || { echo "FAIL: epic card missing Integration checklist section"; exit 1; }

# --- staged in git, not committed -------------------------------------------

git -C "$REPO" diff --cached --name-only | grep -qF "$(basename "$PATH1")" || { echo "FAIL: new card not staged"; exit 1; }
[ -z "$(git -C "$REPO" log --oneline 2>/dev/null || true)" ] || { echo "FAIL: kanban-new.sh must never commit"; exit 1; }

echo "PASS new"
