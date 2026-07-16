#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
rc=0
for t in "$HERE"/*.test.sh; do
  echo "== $(basename "$t") =="
  bash "$t" || rc=1
done
[ "$rc" = 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$rc"
