#!/usr/bin/env bash
# move.test.sh — happy-path forward move, done blocked without --approved,
# and grooming exit blocked while Open questions remain.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KNEW="$HERE/../scripts/kanban-new.sh"
KMOVE="$HERE/../scripts/kanban-move.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
git_c() { git -c user.email=t@t -c user.name=t -c init.defaultBranch=main "$@"; }

REPO="$TMP/myrepo"
mkdir -p "$REPO"; git_c -C "$REPO" init -q
export KANBAN_PREFIX_REGISTRY="$TMP/registry.tsv"

# --- happy path: todo -> progress -------------------------------------------

CARD="$(bash "$KNEW" --repo "$REPO" --title "Move me" --stage todo --prefix K)"
OUT="$(bash "$KMOVE" --repo "$REPO" K-001 progress 2>/tmp/move-stderr.$$)"
[ "$OUT" = "$REPO/.agents/kanban/progress/K-001-move-me.md" ] || { echo "FAIL: unexpected move destination: $OUT"; exit 1; }
grep -q '^task: start K-001 (todo→progress)$' /tmp/move-stderr.$$ || { echo "FAIL: unexpected commit-subject line"; cat /tmp/move-stderr.$$; exit 1; }
rm -f /tmp/move-stderr.$$
[ -f "$REPO/.agents/kanban/progress/K-001-move-me.md" ] || { echo "FAIL: card not relocated"; exit 1; }
[ -f "$REPO/.agents/kanban/todo/K-001-move-me.md" ] && { echo "FAIL: old path still present"; exit 1; }

# --- forward-skip without --force is rejected -------------------------------

bash "$KNEW" --repo "$REPO" --title "Skip me" --stage todo --prefix K >/dev/null
set +e
bash "$KMOVE" --repo "$REPO" K-002 test >/dev/null 2>/tmp/move-skip-err.$$
rc=$?
set -e
[ "$rc" -eq 2 ] || { echo "FAIL: expected exit 2 (validation) for a rejected forward-skip, got $rc"; exit 1; }
grep -qi "permitted transition" /tmp/move-skip-err.$$ || { echo "FAIL: skip-rejection message unclear"; cat /tmp/move-skip-err.$$; exit 1; }
rm -f /tmp/move-skip-err.$$

# --- grooming exit blocked while Open questions remain ----------------------

GCARD="$(bash "$KNEW" --repo "$REPO" --title "Groom me" --stage grooming --prefix K)"
set +e
bash "$KMOVE" --repo "$REPO" K-003 todo >/dev/null 2>/tmp/move-groom-err.$$
rc=$?
set -e
[ "$rc" -eq 2 ] || { echo "FAIL: expected exit 2 (validation) for grooming->todo blocked by Open questions, got $rc"; exit 1; }
grep -qi "open questions" /tmp/move-groom-err.$$ || { echo "FAIL: grooming-block message unclear"; cat /tmp/move-groom-err.$$; exit 1; }
rm -f /tmp/move-groom-err.$$

# resolve the open questions, then the move should succeed
sed -i '/\*\*Open questions:\*\*/,/^$/d' "$GCARD"
bash "$KMOVE" --repo "$REPO" K-003 todo >/dev/null
[ -f "$REPO/.agents/kanban/todo/K-003-groom-me.md" ] || { echo "FAIL: card did not move after Open questions resolved"; exit 1; }

# --- done requires --approved ------------------------------------------------

bash "$KMOVE" --repo "$REPO" K-001 test --force >/dev/null 2>&1 || true
bash "$KMOVE" --repo "$REPO" K-001 ready --force >/dev/null 2>&1 || true
set +e
bash "$KMOVE" --repo "$REPO" K-001 done >/dev/null 2>/tmp/move-done-err.$$
rc=$?
set -e
[ "$rc" -eq 2 ] || { echo "FAIL: expected exit 2 (validation) for ready->done without --approved, got $rc"; exit 1; }
grep -qi "approved" /tmp/move-done-err.$$ || { echo "FAIL: done-approval message unclear"; cat /tmp/move-done-err.$$; exit 1; }
grep -Fq "explicit current user approval" /tmp/move-done-err.$$ || { echo "FAIL: missing-flag error omits current user authorization form"; cat /tmp/move-done-err.$$; exit 1; }
grep -Fq "recorded upfront task/EPIC/workflow authorization" /tmp/move-done-err.$$ || { echo "FAIL: missing-flag error omits upfront authorization form"; cat /tmp/move-done-err.$$; exit 1; }
grep -Fq "recorded profile/agent authorization" /tmp/move-done-err.$$ || { echo "FAIL: missing-flag error omits profile/agent authorization form"; cat /tmp/move-done-err.$$; exit 1; }
[ -f "$REPO/.agents/kanban/ready/K-001-move-me.md" ] || { echo "FAIL: missing --approved moved the card"; exit 1; }
rm -f /tmp/move-done-err.$$

bash "$KMOVE" --repo "$REPO" K-001 done --approved >/dev/null
[ -f "$REPO/.agents/kanban/done/K-001-move-me.md" ] || { echo "FAIL: approved done move did not happen"; exit 1; }

# --- subtasks wait for their parent epic -------------------------------------

mkdir -p "$REPO/.agents/kanban/ready"
printf '# Parent epic\n' >"$REPO/.agents/kanban/ready/EPIC-001-parent.md"
printf '# Child card\n' >"$REPO/.agents/kanban/ready/EPIC-001-01-child.md"
set +e
bash "$KMOVE" --repo "$REPO" EPIC-001-01 done --approved >/dev/null 2>/tmp/move-parent-err.$$
rc=$?
set -e
[ "$rc" -eq 2 ] || { echo "FAIL: expected exit 2 when child precedes parent, got $rc"; exit 1; }
grep -qi "parent epic" /tmp/move-parent-err.$$ || { echo "FAIL: parent-before-child error unclear"; cat /tmp/move-parent-err.$$; exit 1; }
[ -f "$REPO/.agents/kanban/ready/EPIC-001-01-child.md" ] || { echo "FAIL: child moved before parent was done"; exit 1; }
rm -f /tmp/move-parent-err.$$

bash "$KMOVE" --repo "$REPO" "$REPO/.agents/kanban/ready/EPIC-001-parent.md" done --approved >/dev/null
bash "$KMOVE" --repo "$REPO" EPIC-001-01 done --approved >/dev/null
[ -f "$REPO/.agents/kanban/done/EPIC-001-01-child.md" ] || { echo "FAIL: child did not move after parent was done"; exit 1; }

# --- --force backward transition prints the "move" verb, not "back" --------

bash "$KNEW" --repo "$REPO" --title "Force back" --stage todo --prefix K >/dev/null
bash "$KMOVE" --repo "$REPO" K-004 progress >/dev/null 2>/dev/null
bash "$KMOVE" --repo "$REPO" K-004 todo --force >/dev/null 2>/tmp/move-back-err.$$
grep -q '^task: move K-004 (progress→todo)$' /tmp/move-back-err.$$ || { echo "FAIL: expected 'task: move ...' verb for a backward transition"; cat /tmp/move-back-err.$$; exit 1; }
rm -f /tmp/move-back-err.$$

echo "PASS move"
