#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; BUILD="$HERE/../build-catalog.sh"; IMPORT="$HERE/../import-skill.sh"
TMP="$(mktemp -d)"; trap 'rm -rf -- "$TMP"' EXIT
git_c() { git -c user.email=t@t -c user.name=t -c init.defaultBranch=main "$@"; }
SRC="$TMP/src"; mkdir -p "$SRC/react"; printf -- '---\nname: react\ndescription: React best practices.\n---\n# React\n' > "$SRC/react/SKILL.md"
git_c init -q "$SRC"; git_c -C "$SRC" add -- react/SKILL.md; git_c -C "$SRC" commit -qm init
SOURCES="$TMP/sources.tsv"; printf 'mysrc\tfile://%s\tskills-repo\n' "$SRC" > "$SOURCES"
CACHE="$TMP/cache"; CAT="$TMP/catalog.tsv"; bash "$BUILD" --refresh --cache "$CACHE" --sources "$SOURCES" --out "$CAT"
PROJ="$TMP/proj"; mkdir -p "$PROJ"; git_c init -q "$PROJ"
bash "$IMPORT" mysrc react --project "$PROJ" --cache "$CACHE" --catalog "$CAT" --sources "$SOURCES"
[ -f "$PROJ/.agents/skills/react/SKILL.md" ] || { echo 'FAIL: not copied'; exit 1; }
[ ! -e "$PROJ/.agents/skills/.imported.tsv" ] || { echo 'FAIL: unexpected manifest'; exit 1; }
[ -z "$(git -C "$PROJ" diff --cached --name-only)" ] || { echo 'FAIL: index changed'; exit 1; }
set +e; bash "$IMPORT" mysrc react --project "$PROJ" --cache "$CACHE" --catalog "$CAT" --sources "$SOURCES" >/dev/null 2>&1; rc=$?; set -e
[ "$rc" = 3 ] || { echo "FAIL: expected collision exit 3, got $rc"; exit 1; }
echo 'PASS import local without staging'
