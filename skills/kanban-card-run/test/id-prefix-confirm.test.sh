#!/usr/bin/env bash
# id-prefix-confirm.test.sh — the exact regression list for the "first
# prefix choice must be confirmed, never auto-picked" fix:
#   1. mixed board, no lock, non-TTY -> next exits 2, lock file NOT created,
#      stderr lists all board prefixes with counts.
#   2. single-prefix legacy board (K-), no lock -> still exits 2
#      (confirmation required even when obvious); set-prefix K persists;
#      next then yields K-<max+1>.
#   3. --prefix PERF next on a lockless mixed board works and persists.
#   4. KANBAN_ASSUME_YES=1 next picks the dominant prefix and prints the
#      persistence notice.
#   5. peek on a lockless board still answers, and still writes nothing.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KID="$HERE/../scripts/kanban-id.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
git_c() { git -c user.email=t@t -c user.name=t -c init.defaultBranch=main "$@"; }

mk_mixed_board() { # <repo>
  local repo="$1"
  mkdir -p "$repo/.claude/kanban/todo"
  git_c -C "$repo" init -q
  local n
  for n in 01 02 03 04 05; do : > "$repo/.claude/kanban/todo/A24-${n}-card.md"; done
  for n in 01 02;          do : > "$repo/.claude/kanban/todo/PERF-${n}-card.md"; done
  for n in 01;             do : > "$repo/.claude/kanban/todo/CLS-${n}-card.md"; done
}

# --- 1: mixed board, no lock, non-TTY -> next exits 2, nothing written ----

REPO1="$TMP/mixed1"
mk_mixed_board "$REPO1"
export KANBAN_PREFIX_REGISTRY="$TMP/reg1.tsv"

set +e
bash "$KID" --repo "$REPO1" next </dev/null >/tmp/confirm1-out.$$ 2>/tmp/confirm1-err.$$
rc=$?
set -e
[ "$rc" -eq 2 ] || { echo "FAIL(1): expected exit 2, got $rc"; cat /tmp/confirm1-err.$$; exit 1; }
[ -s /tmp/confirm1-out.$$ ] && { echo "FAIL(1): next must not print anything on stdout when unconfirmed"; exit 1; }
[ -f "$REPO1/.claude/kanban.lock" ] && { echo "FAIL(1): lock file must NOT be created"; exit 1; }
for p in A24 PERF CLS; do
  grep -q "$p" /tmp/confirm1-err.$$ || { echo "FAIL(1): candidate list missing $p"; cat /tmp/confirm1-err.$$; exit 1; }
done
grep -q "A24.*5 card(s)" /tmp/confirm1-err.$$ || { echo "FAIL(1): A24 count wrong"; cat /tmp/confirm1-err.$$; exit 1; }
rm -f /tmp/confirm1-out.$$ /tmp/confirm1-err.$$

# --- 2: single-prefix legacy board, no lock -> still exits 2 (obvious or --
#        not); set-prefix K persists; next yields K-<max+1> ----------------

REPO2="$TMP/legacy2"
mkdir -p "$REPO2/.claude/kanban/todo"
git_c -C "$REPO2" init -q
for n in 001 002 076; do : > "$REPO2/.claude/kanban/todo/K-${n}-card.md"; done
export KANBAN_PREFIX_REGISTRY="$TMP/reg2.tsv"

set +e
bash "$KID" --repo "$REPO2" next </dev/null >/dev/null 2>/tmp/confirm2-err.$$
rc=$?
set -e
[ "$rc" -eq 2 ] || { echo "FAIL(2): expected exit 2 even for an obvious single-prefix board, got $rc"; exit 1; }
rm -f /tmp/confirm2-err.$$

bash "$KID" --repo "$REPO2" set-prefix K >/dev/null
ID2="$(bash "$KID" --repo "$REPO2" next)"
[ "$ID2" = "K-077" ] || { echo "FAIL(2): expected K-077 (max existing 076 + 1), got $ID2"; exit 1; }

# --- 3: --prefix PERF next on a lockless mixed board works and persists ---

REPO3="$TMP/mixed3"
mk_mixed_board "$REPO3"
export KANBAN_PREFIX_REGISTRY="$TMP/reg3.tsv"

ID3="$(bash "$KID" --repo "$REPO3" next PERF 2>/tmp/confirm3-err.$$)"
[ "$ID3" = "PERF-03" ] || { echo "FAIL(3): expected PERF-03 (max existing 02 + 1), got $ID3"; exit 1; }
grep -qF "PERF" /tmp/confirm3-err.$$ || { echo "FAIL(3): expected a persistence notice on stderr"; cat /tmp/confirm3-err.$$; exit 1; }
grep -q "^prefix=PERF$" "$REPO3/.claude/kanban.lock" || { echo "FAIL(3): explicit --prefix should persist as the project default on first use"; cat "$REPO3/.claude/kanban.lock"; exit 1; }
rm -f /tmp/confirm3-err.$$

# --- 4: KANBAN_ASSUME_YES=1 next picks the dominant prefix + notice -------

REPO4="$TMP/mixed4"
mk_mixed_board "$REPO4"
export KANBAN_PREFIX_REGISTRY="$TMP/reg4.tsv"

ID4="$(KANBAN_ASSUME_YES=1 bash "$KID" --repo "$REPO4" next 2>/tmp/confirm4-err.$$)"
[ "$ID4" = "A24-06" ] || { echo "FAIL(4): expected A24-06 (dominant prefix, max existing 05 + 1), got $ID4"; exit 1; }
grep -qi "A24" /tmp/confirm4-err.$$ || { echo "FAIL(4): expected the persistence notice to name A24"; cat /tmp/confirm4-err.$$; exit 1; }
grep -qi "written to" /tmp/confirm4-err.$$ || { echo "FAIL(4): expected the notice to say where it was written"; cat /tmp/confirm4-err.$$; exit 1; }
rm -f /tmp/confirm4-err.$$

# --- 5: peek on a lockless board still answers, writes nothing -----------

REPO5="$TMP/mixed5"
mk_mixed_board "$REPO5"
export KANBAN_PREFIX_REGISTRY="$TMP/reg5.tsv"

PK5="$(bash "$KID" --repo "$REPO5" peek)"
[ "$PK5" = "A24-05" ] || { echo "FAIL(5): expected peek to resolve A24-05 (dominant), got $PK5"; exit 1; }
[ -f "$REPO5/.claude/kanban.lock" ] && { echo "FAIL(5): peek must not write kanban.lock"; exit 1; }
[ -f "$TMP/reg5.tsv" ] && { echo "FAIL(5): peek must not write the prefix registry"; exit 1; }

echo "PASS id-prefix-confirm"
