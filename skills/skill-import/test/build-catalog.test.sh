#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../build-catalog.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
git_c() { git -c user.email=t@t -c user.name=t -c init.defaultBranch=main "$@"; }

# fixture source repo with two skill dirs
SRC="$TMP/src"; mkdir -p "$SRC/react" "$SRC/docker/nested"
cat >"$SRC/react/SKILL.md" <<'EOF'
---
name: react
description: React best practices and hooks. Use for React apps.
---
# React
EOF
cat >"$SRC/docker/nested/SKILL.md" <<'EOF'
---
name: docker-nested
description: Docker guidance.
---
EOF
git_c init -q "$SRC"; git_c -C "$SRC" add -A; git_c -C "$SRC" commit -qm init

SOURCES="$TMP/sources.tsv"
printf 'mysrc\tfile://%s\tskills-repo\n' "$SRC" >"$SOURCES"
CACHE="$TMP/cache"; OUT="$TMP/catalog.tsv"

bash "$SCRIPT" --cache "$CACHE" --sources "$SOURCES" --out "$OUT"

grep -qP '^mysrc\treact\tlocal\treact\tReact best practices' "$OUT" || { echo "FAIL: react row"; cat "$OUT"; exit 1; }
grep -qP '^mysrc\tdocker-nested\tlocal\tdocker/nested\t' "$OUT" || { echo "FAIL: nested row"; cat "$OUT"; exit 1; }
echo "PASS build-catalog local"
