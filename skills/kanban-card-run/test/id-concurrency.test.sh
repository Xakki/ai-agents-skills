#!/usr/bin/env bash
# id-concurrency.test.sh — 5 parallel `kanban-id.sh next` allocations under
# the same prefix must produce 5 distinct IDs (flock/mkdir-spinlock guard).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KID="$HERE/../scripts/kanban-id.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
git_c() { git -c user.email=t@t -c user.name=t -c init.defaultBranch=main "$@"; }

REPO="$TMP/myrepo"
mkdir -p "$REPO"; git_c -C "$REPO" init -q
export KANBAN_PREFIX_REGISTRY="$TMP/registry.tsv"

OUTDIR="$TMP/out"; mkdir -p "$OUTDIR"
pids=()
for i in 1 2 3 4 5; do
  ( bash "$KID" --repo "$REPO" next K > "$OUTDIR/$i.out" ) &
  pids+=($!)
done
for p in "${pids[@]}"; do wait "$p"; done

RESULTS="$(cat "$OUTDIR"/*.out | sort -u)"
COUNT="$(printf '%s\n' "$RESULTS" | grep -c .)"
[ "$COUNT" -eq 5 ] || { echo "FAIL: expected 5 distinct IDs, got $COUNT:"; echo "$RESULTS"; exit 1; }

EXPECTED="$(printf 'K-%03d\n' 1 2 3 4 5)"
[ "$RESULTS" = "$EXPECTED" ] || { echo "FAIL: expected K-001..K-005, got:"; echo "$RESULTS"; exit 1; }

echo "PASS id-concurrency"
