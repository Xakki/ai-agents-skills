#!/usr/bin/env bash
# id-prefix-legacy-board.test.sh — a board that already has cards but no
# kanban.lock must never get a fresh dir-name-derived prefix auto-picked
# (that would silently split the board's ID space) — confirmation is always
# required first, even when a dominant prefix is obvious. Covers: a
# single-prefix legacy board (confirm-required, then set-prefix, then next),
# a mixed-prefix board (candidate list ordered by count), a genuinely empty
# board (still confirm-required; dir-name-derived candidate shown as the
# fallback), no duplicate registry rows on a cross-repo prefix collision, and
# read-only `peek` resolving the dominant prefix on a lockless board without
# writing anything.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KID="$HERE/../scripts/kanban-id.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
git_c() { git -c user.email=t@t -c user.name=t -c init.defaultBranch=main "$@"; }

# --- (a) single-prefix legacy board: confirm required, then set-prefix ----

REPO_A="$TMP/legacy-avito-fix"
mkdir -p "$REPO_A/.claude/kanban/todo" "$REPO_A/.claude/kanban/done"
git_c -C "$REPO_A" init -q
for n in 001 002 003 074; do
  : > "$REPO_A/.claude/kanban/todo/K-${n}-card.md"
done
: > "$REPO_A/.claude/kanban/done/K-070-old-card.md"
export KANBAN_PREFIX_REGISTRY="$TMP/registry-a.tsv"

[ -f "$REPO_A/.claude/kanban.lock" ] && { echo "FAIL: lock file should not pre-exist"; exit 1; }

set +e
bash "$KID" --repo "$REPO_A" prefix </dev/null >/dev/null 2>/tmp/legacy-a-err.$$
rc=$?
set -e
[ "$rc" -eq 2 ] || { echo "FAIL(a): expected exit 2 (confirmation required), got $rc"; cat /tmp/legacy-a-err.$$; exit 1; }
grep -q "K .*5 card(s)" /tmp/legacy-a-err.$$ || { echo "FAIL(a): candidate list missing K with 5 cards"; cat /tmp/legacy-a-err.$$; exit 1; }
[ -f "$REPO_A/.claude/kanban.lock" ] && { echo "FAIL(a): lock file must not be created before confirmation"; exit 1; }
rm -f /tmp/legacy-a-err.$$

bash "$KID" --repo "$REPO_A" set-prefix K >/dev/null
ID="$(bash "$KID" --repo "$REPO_A" next)"
[ "$ID" = "K-075" ] || { echo "FAIL(a): expected K-075 (max existing 074 + 1) after set-prefix, got $ID"; exit 1; }

# --- (b) mixed-prefix board: candidate list ordered by count --------------

REPO_B="$TMP/mixed-board"
mkdir -p "$REPO_B/.claude/kanban/todo"
git_c -C "$REPO_B" init -q
for n in 01 02 03 04 05; do
  : > "$REPO_B/.claude/kanban/todo/A24-${n}-card.md"
done
for n in 01 02; do
  : > "$REPO_B/.claude/kanban/todo/PERF-${n}-card.md"
done
export KANBAN_PREFIX_REGISTRY="$TMP/registry-b.tsv"

set +e
bash "$KID" --repo "$REPO_B" prefix </dev/null >/dev/null 2>/tmp/legacy-b-err.$$
rc=$?
set -e
[ "$rc" -eq 2 ] || { echo "FAIL(b): expected exit 2, got $rc"; exit 1; }
A24_LINE="$(grep -n 'A24' /tmp/legacy-b-err.$$ | head -n1 | cut -d: -f1)"
PERF_LINE="$(grep -n 'PERF' /tmp/legacy-b-err.$$ | head -n1 | cut -d: -f1)"
[ -n "$A24_LINE" ] && [ -n "$PERF_LINE" ] || { echo "FAIL(b): candidate list missing A24/PERF"; cat /tmp/legacy-b-err.$$; exit 1; }
[ "$A24_LINE" -lt "$PERF_LINE" ] || { echo "FAIL(b): A24 (5 cards) should be listed before PERF (2 cards)"; cat /tmp/legacy-b-err.$$; exit 1; }
grep -q "for autonomous.*KANBAN_ASSUME_YES=1 to accept 'A24'" /tmp/legacy-b-err.$$ || { echo "FAIL(b): top candidate for auto-accept should be A24"; cat /tmp/legacy-b-err.$$; exit 1; }
rm -f /tmp/legacy-b-err.$$

# --- (c) empty board: still confirm-required; dir-derived shown as fallback

REPO_C="$TMP/avito-fix"
mkdir -p "$REPO_C"
git_c -C "$REPO_C" init -q
export KANBAN_PREFIX_REGISTRY="$TMP/registry-c.tsv"

set +e
bash "$KID" --repo "$REPO_C" prefix </dev/null >/dev/null 2>/tmp/legacy-c-err.$$
rc=$?
set -e
[ "$rc" -eq 2 ] || { echo "FAIL(c): expected exit 2, got $rc"; exit 1; }
grep -qi "no existing cards" /tmp/legacy-c-err.$$ || { echo "FAIL(c): expected an empty-board notice"; cat /tmp/legacy-c-err.$$; exit 1; }
grep -q "AVF" /tmp/legacy-c-err.$$ || { echo "FAIL(c): expected dir-derived candidate AVF mentioned"; cat /tmp/legacy-c-err.$$; exit 1; }
rm -f /tmp/legacy-c-err.$$

PC="$(KANBAN_ASSUME_YES=1 bash "$KID" --repo "$REPO_C" prefix 2>/dev/null)"
[ "$PC" = "AVF" ] || { echo "FAIL(c): expected dir-derived AVF once accepted, got $PC"; exit 1; }

# --- (d) two legacy boards adopting the SAME dominant prefix share one -----
# registry row: adoption must not append a second row for an already-claimed
# prefix (registry stays "one row per reserved prefix", per scripts.md).

REPO_D1="$TMP/legacy-one"
mkdir -p "$REPO_D1/.claude/kanban/todo"
git_c -C "$REPO_D1" init -q
: > "$REPO_D1/.claude/kanban/todo/K-001-card.md"

REPO_D2="$TMP/legacy-two"
mkdir -p "$REPO_D2/.claude/kanban/todo"
git_c -C "$REPO_D2" init -q
: > "$REPO_D2/.claude/kanban/todo/K-050-card.md"

SHARED_REG="$TMP/registry-shared.tsv"
export KANBAN_PREFIX_REGISTRY="$SHARED_REG"

KANBAN_ASSUME_YES=1 bash "$KID" --repo "$REPO_D1" prefix >/dev/null 2>&1
PD2="$(KANBAN_ASSUME_YES=1 bash "$KID" --repo "$REPO_D2" prefix 2>/tmp/legacy-collide-err.$$)"
[ "$PD2" = "K" ] || { echo "FAIL(d): expected repo D2 to also adopt K, got $PD2"; exit 1; }
grep -qi "already registered" /tmp/legacy-collide-err.$$ || { echo "FAIL(d): expected a collision warning on stderr"; cat /tmp/legacy-collide-err.$$; exit 1; }
rm -f /tmp/legacy-collide-err.$$

ROWS="$(grep -c '^K	' "$SHARED_REG")"
[ "$ROWS" -eq 1 ] || { echo "FAIL(d): expected exactly 1 registry row for prefix K, got $ROWS"; cat "$SHARED_REG"; exit 1; }

# --- (e) `peek` on a lockless legacy board resolves READ-ONLY --------------
# (no explicit PREFIX, no prefix= yet) — must answer from the dominant board
# prefix without writing kanban.lock or the registry (only an actual
# allocation reserves; peek is unaffected by the confirm-required contract).

REPO_E="$TMP/legacy-peek"
mkdir -p "$REPO_E/.claude/kanban/todo"
git_c -C "$REPO_E" init -q
for n in 001 002 076; do
  : > "$REPO_E/.claude/kanban/todo/K-${n}-card.md"
done
export KANBAN_PREFIX_REGISTRY="$TMP/registry-e.tsv"

PE="$(bash "$KID" --repo "$REPO_E" peek)"
[ "$PE" = "K-076" ] || { echo "FAIL(e): expected peek to resolve K-076 on a lockless board, got $PE"; exit 1; }
[ -f "$REPO_E/.claude/kanban.lock" ] && { echo "FAIL(e): peek must not write kanban.lock"; exit 1; }
[ -f "$TMP/registry-e.tsv" ] && { echo "FAIL(e): peek must not write the prefix registry"; exit 1; }

echo "PASS id-prefix-legacy-board"
