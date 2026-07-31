#!/usr/bin/env bash
# id-basics.test.sh — fresh-repo prefix confirmation is REQUIRED (never
# auto-picked); KANBAN_ASSUME_YES=1 accepts it; then first ID, idempotent
# prefix lookup once persisted, and independent counters for a second
# explicit prefix.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KID="$HERE/../scripts/kanban-id.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
git_c() { git -c user.email=t@t -c user.name=t -c init.defaultBranch=main "$@"; }

REPO="$TMP/myrepo"
mkdir -p "$REPO"; git_c -C "$REPO" init -q
export KANBAN_PREFIX_REGISTRY="$TMP/registry.tsv"

# a fresh, empty board with no lock file requires confirmation before a
# default prefix is ever picked — never auto-persisted, nothing written.
set +e
bash "$KID" --repo "$REPO" prefix </dev/null >/dev/null 2>/tmp/id-basics-err.$$
rc=$?
set -e
[ "$rc" -eq 2 ] || { echo "FAIL: expected exit 2 (confirmation required) on first use, got $rc"; cat /tmp/id-basics-err.$$; exit 1; }
[ -f "$REPO/.claude/kanban.lock" ] && { echo "FAIL: lock file must not be created before confirmation"; exit 1; }
rm -f /tmp/id-basics-err.$$

P1="$(KANBAN_ASSUME_YES=1 bash "$KID" --repo "$REPO" prefix 2>/dev/null)"
[ -n "$P1" ] || { echo "FAIL: empty prefix after KANBAN_ASSUME_YES=1"; exit 1; }

# once persisted, further calls resolve straight away — no confirmation needed
P2="$(bash "$KID" --repo "$REPO" prefix </dev/null)"
[ "$P1" = "$P2" ] || { echo "FAIL: prefix not idempotent: $P1 vs $P2"; exit 1; }

ID1="$(bash "$KID" --repo "$REPO" next)"
[ "$ID1" = "${P1}-001" ] || { echo "FAIL: expected ${P1}-001, got $ID1"; exit 1; }

ID2="$(bash "$KID" --repo "$REPO" next)"
[ "$ID2" = "${P1}-002" ] || { echo "FAIL: expected ${P1}-002, got $ID2"; exit 1; }

# an independent, explicitly-named prefix keeps its own counter
O1="$(bash "$KID" --repo "$REPO" next OTHER)"
[ "$O1" = "OTHER-001" ] || { echo "FAIL: expected OTHER-001, got $O1"; exit 1; }
O2="$(bash "$KID" --repo "$REPO" next OTHER)"
[ "$O2" = "OTHER-002" ] || { echo "FAIL: expected OTHER-002, got $O2"; exit 1; }

# peek reads back the last allocated ID without allocating
PK="$(bash "$KID" --repo "$REPO" peek)"
[ "$PK" = "$ID2" ] || { echo "FAIL: peek expected $ID2, got $PK"; exit 1; }

grep -q "^prefix=${P1}$" "$REPO/.claude/kanban.lock" || { echo "FAIL: lock file missing prefix line"; cat "$REPO/.claude/kanban.lock"; exit 1; }
grep -q "^${P1}=2$" "$REPO/.claude/kanban.lock" || { echo "FAIL: lock file counter wrong"; cat "$REPO/.claude/kanban.lock"; exit 1; }
grep -q "^OTHER=2$" "$REPO/.claude/kanban.lock" || { echo "FAIL: lock file OTHER counter wrong"; cat "$REPO/.claude/kanban.lock"; exit 1; }

echo "PASS id-basics"
