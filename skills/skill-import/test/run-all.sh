#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
rc=0
for t in "$HERE"/*.test.sh; do
  echo "== $(basename "$t") =="
  bash "$t" || rc=1
done
echo '== test_safe_import.py =='
python3 "$HERE/test_safe_import.py" || rc=1
echo '== test_update_skill.py =='
python3 "$HERE/test_update_skill.py" || rc=1
[ "$rc" = 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$rc"
