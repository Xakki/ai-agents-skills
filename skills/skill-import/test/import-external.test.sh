#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMPORT="$HERE/../import-skill.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
git_c() { git -c user.email=t@t -c user.name=t -c init.defaultBranch=main "$@"; }

# external repo with SKILL.md at root
EXT="$TMP/ext"; mkdir -p "$EXT"
printf -- '---\nname: aws-skills\ndescription: AWS helpers.\n---\n# AWS\n' >"$EXT/SKILL.md"
git_c init -q "$EXT"; git_c -C "$EXT" add -A; git_c -C "$EXT" commit -qm init

CACHE="$TMP/cache"; mkdir -p "$CACHE"
CAT="$TMP/catalog.tsv"
printf 'source\tskill\tkind\tlocation\tdescription\n' >"$CAT"
printf 'aw\taws-skills\texternal\tfile://%s\tAWS helpers.\n' "$EXT" >>"$CAT"

PROJ="$TMP/proj"; mkdir -p "$PROJ"; git_c init -q "$PROJ"
bash "$IMPORT" aw aws-skills --project "$PROJ" --cache "$CACHE" --catalog "$CAT"

[ -f "$PROJ/.claude/skills/aws-skills/SKILL.md" ] || { echo "FAIL: external not copied"; exit 1; }
grep -qP '^aws-skills\taw\tfile://.*\t\.\t[0-9a-f]{7,}\t' "$PROJ/.claude/skills/.imported.tsv" || { echo "FAIL: external manifest"; cat "$PROJ/.claude/skills/.imported.tsv"; exit 1; }

[ ! -e "$PROJ/.claude/skills/aws-skills/.git" ] || { echo "FAIL: .git copied"; exit 1; }
git -C "$PROJ" diff --cached --name-only | grep -q '.claude/skills/aws-skills/SKILL.md' || { echo "FAIL: SKILL.md not staged as file"; exit 1; }

echo "PASS import-skill external"
