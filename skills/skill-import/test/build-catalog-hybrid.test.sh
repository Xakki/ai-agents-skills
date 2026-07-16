#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../build-catalog.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
git_c() { git -c user.email=t@t -c user.name=t -c init.defaultBranch=main "$@"; }

SRC="$TMP/src"; mkdir -p "$SRC/local-one"
cat >"$SRC/local-one/SKILL.md" <<'EOF'
---
name: local-one
description: A local skill.
---
EOF
cat >"$SRC/README.md" <<'EOF'
# Awesome
## Skills
- [AWS Skills](https://github.com/zxkane/aws-skills) — AWS helpers for Claude.
- [Playwright](https://github.com/lackeyjb/playwright-skill) - browser automation.
- [Not a skill](https://example.com/blog) — ignored, not github.
EOF
git_c init -q "$SRC"; git_c -C "$SRC" add -A; git_c -C "$SRC" commit -qm init

SOURCES="$TMP/sources.tsv"
printf 'aw\tfile://%s\thybrid\n' "$SRC" >"$SOURCES"
CACHE="$TMP/cache"; OUT="$TMP/catalog.tsv"
bash "$SCRIPT" --cache "$CACHE" --sources "$SOURCES" --out "$OUT"

grep -qP '^aw\tlocal-one\tlocal\t' "$OUT" || { echo "FAIL local in hybrid"; cat "$OUT"; exit 1; }
grep -qP '^aw\taws-skills\texternal\thttps://github.com/zxkane/aws-skills\tAWS helpers' "$OUT" || { echo "FAIL external aws"; cat "$OUT"; exit 1; }
grep -qP '^aw\tplaywright-skill\texternal\thttps://github.com/lackeyjb/playwright-skill\tbrowser automation' "$OUT" || { echo "FAIL external pw"; cat "$OUT"; exit 1; }
grep -q 'example.com' "$OUT" && { echo "FAIL: non-github link leaked"; exit 1; }
echo "PASS build-catalog hybrid"
