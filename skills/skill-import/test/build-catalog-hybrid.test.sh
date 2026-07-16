#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../build-catalog.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
git_c() { git -c user.email=t@t -c user.name=t -c init.defaultBranch=main "$@"; }

SRC="$TMP/src"; mkdir -p "$SRC/local-one" "$SRC/quoted-one"
cat >"$SRC/local-one/SKILL.md" <<'EOF'
---
name: local-one
description: A local skill.
---
EOF
cat >"$SRC/quoted-one/SKILL.md" <<'EOF'
---
name: quoted-one
description: "Quoted desc"
---
EOF
cat >"$SRC/README.md" <<'EOF'
# Awesome
## Skills
- [AWS Skills](https://github.com/zxkane/aws-skills) — AWS helpers for Claude.
- [Playwright](https://github.com/lackeyjb/playwright-skill) - browser automation.
- [Not a skill](https://example.com/blog) — ignored, not github.
- [Real Skill](https://github.com/org/real-skill) — Does a real thing. *By [@user](https://github.com/user)*
EOF
git_c init -q "$SRC"; git_c -C "$SRC" add -A; git_c -C "$SRC" commit -qm init

SOURCES="$TMP/sources.tsv"
printf 'aw\tfile://%s\thybrid\n' "$SRC" >"$SOURCES"
CACHE="$TMP/cache"; OUT="$TMP/catalog.tsv"
bash "$SCRIPT" --cache "$CACHE" --sources "$SOURCES" --out "$OUT"

grep -qP '^aw\tlocal-one\tlocal\t' "$OUT" || { echo "FAIL local in hybrid"; cat "$OUT"; exit 1; }
grep -qP '^aw\tquoted-one\tlocal\tquoted-one\tQuoted desc$' "$OUT" || { echo "FAIL: quoted description not stripped"; cat "$OUT"; exit 1; }
grep -qP '^aw\taws-skills\texternal\thttps://github.com/zxkane/aws-skills\tAWS helpers' "$OUT" || { echo "FAIL external aws"; cat "$OUT"; exit 1; }
grep -qP '^aw\tplaywright-skill\texternal\thttps://github.com/lackeyjb/playwright-skill\tbrowser automation' "$OUT" || { echo "FAIL external pw"; cat "$OUT"; exit 1; }
grep -q 'example.com' "$OUT" && { echo "FAIL: non-github link leaked"; exit 1; }

# regression: a second (attribution) markdown link on the same line must not
# hijack the URL/description — the FIRST github link wins.
grep -qP '^aw\treal-skill\texternal\thttps://github.com/org/real-skill\tDoes a real thing' "$OUT" || { echo "FAIL external real-skill (attribution suffix)"; cat "$OUT"; exit 1; }
awk -F'\t' '$4=="https://github.com/user"' "$OUT" | grep -q . && { echo "FAIL: attribution link leaked as its own row"; cat "$OUT"; exit 1; }
awk -F'\t' '$2=="user"' "$OUT" | grep -q . && { echo "FAIL: attribution username leaked as skill column"; cat "$OUT"; exit 1; }

echo "PASS build-catalog hybrid"
