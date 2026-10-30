#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; BUILD="$HERE/../build-catalog.sh"; IMPORT="$HERE/../import-skill.sh"; UPDATE="$HERE/../update-imported.sh"
TMP="$(mktemp -d)"; trap 'rm -rf -- "$TMP"' EXIT
git_c() { git -c user.email=t@t -c user.name=t -c init.defaultBranch=main "$@"; }
SRC="$TMP/src"; mkdir -p "$SRC/react"; printf -- '---\nname: react\ndescription: v1.\n---\n# v1\n' > "$SRC/react/SKILL.md"
git_c init -q "$SRC"; git_c -C "$SRC" add -- react/SKILL.md; git_c -C "$SRC" commit -qm v1
SOURCES="$TMP/sources.tsv"; printf 'mysrc\tfile://%s\tskills-repo\n' "$SRC" > "$SOURCES"; CACHE="$TMP/cache"; CAT="$TMP/catalog.tsv"
bash "$BUILD" --refresh --cache "$CACHE" --sources "$SOURCES" --out "$CAT"
PROJ="$TMP/proj"; mkdir -p "$PROJ"; git_c init -q "$PROJ"; bash "$IMPORT" mysrc react --project "$PROJ" --cache "$CACHE" --catalog "$CAT" --sources "$SOURCES"
printf 'react\tmysrc\tfile://%s\treact\told\t2020-01-01\n' "$SRC" > "$PROJ/.agents/skills/.imported.tsv"; cp "$PROJ/.agents/skills/.imported.tsv" "$TMP/original"
printf -- '---\nname: react\ndescription: v2.\n---\n# v2\n' > "$SRC/react/SKILL.md"; git_c -C "$SRC" commit -qam v2
bash "$BUILD" --refresh --cache "$CACHE" --sources "$SOURCES" --out "$CAT"
set +e; bash "$UPDATE" react --project "$PROJ" --cache "$CACHE" --catalog "$CAT" --sources "$SOURCES" >/dev/null 2>&1; rc=$?; set -e
[ "$rc" = 4 ] || { echo "FAIL: expected preview difference, got $rc"; exit 1; }
set +e; bash "$UPDATE" react --project "$PROJ" --cache "$CACHE" --catalog "$CAT" --sources "$SOURCES" --force >/dev/null 2>&1; rc=$?; set -e
[ "$rc" != 0 ] || { echo 'FAIL: force update must be refused'; exit 1; }
grep -q '# v1' "$PROJ/.agents/skills/react/SKILL.md"; cmp "$TMP/original" "$PROJ/.agents/skills/.imported.tsv"
[ -z "$(git -C "$PROJ" diff --cached --name-only)" ] || { echo 'FAIL: index changed'; exit 1; }
echo 'PASS update preview preserves project'
