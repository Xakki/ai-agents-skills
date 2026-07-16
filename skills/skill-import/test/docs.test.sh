#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SK="$HERE/../SKILL.md"; REF="$HERE/../reference.md"
[ -f "$SK" ] || { echo "FAIL: no SKILL.md"; exit 1; }
[ -f "$REF" ] || { echo "FAIL: no reference.md"; exit 1; }
head -1 "$SK" | grep -q '^---$' || { echo "FAIL: no frontmatter"; exit 1; }
grep -qP '^name:[[:space:]]*skill-import[[:space:]]*$' "$SK" || { echo "FAIL: name"; exit 1; }
grep -qi 'description:.*import' "$SK" || { echo "FAIL: description keyword"; exit 1; }
grep -q 'Триггеры' "$SK" || { echo "FAIL: RU triggers"; exit 1; }
grep -q 'build-catalog.sh' "$SK" || { echo "FAIL: no script ref"; exit 1; }
grep -qi 'subagent' "$SK" || { echo "FAIL: no delegation note"; exit 1; }
echo "PASS docs"
