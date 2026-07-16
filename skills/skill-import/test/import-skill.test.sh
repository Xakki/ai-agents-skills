#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$HERE/../build-catalog.sh"; IMPORT="$HERE/../import-skill.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
git_c() { git -c user.email=t@t -c user.name=t -c init.defaultBranch=main "$@"; }

SRC="$TMP/src"; mkdir -p "$SRC/react"
printf -- '---\nname: react\ndescription: React best practices.\n---\n# React\n' >"$SRC/react/SKILL.md"
git_c init -q "$SRC"; git_c -C "$SRC" add -A; git_c -C "$SRC" commit -qm init

SOURCES="$TMP/sources.tsv"; printf 'mysrc\tfile://%s\tskills-repo\n' "$SRC" >"$SOURCES"
CACHE="$TMP/cache"; CAT="$TMP/catalog.tsv"
bash "$BUILD" --cache "$CACHE" --sources "$SOURCES" --out "$CAT"

PROJ="$TMP/proj"; mkdir -p "$PROJ"; git_c init -q "$PROJ"
bash "$IMPORT" mysrc react --project "$PROJ" --cache "$CACHE" --catalog "$CAT"

[ -f "$PROJ/.claude/skills/react/SKILL.md" ] || { echo "FAIL: not copied"; exit 1; }
grep -qP '^react\tmysrc\tfile://.*\treact\t[0-9a-f]{7,}\t' "$PROJ/.claude/skills/.imported.tsv" || { echo "FAIL: manifest"; cat "$PROJ/.claude/skills/.imported.tsv"; exit 1; }
git -C "$PROJ" diff --cached --name-only | grep -q '.claude/skills/react/SKILL.md' || { echo "FAIL: not staged"; exit 1; }

# collision without --force exits 3
set +e; bash "$IMPORT" mysrc react --project "$PROJ" --cache "$CACHE" --catalog "$CAT" >/dev/null 2>&1; rc=$?; set -e
[ "$rc" = 3 ] || { echo "FAIL: expected exit 3 on collision, got $rc"; exit 1; }
echo "PASS import-skill local"
