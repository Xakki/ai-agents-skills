#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$HERE/../build-catalog.sh"; IMPORT="$HERE/../import-skill.sh"; UPDATE="$HERE/../update-imported.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
git_c() { git -c user.email=t@t -c user.name=t -c init.defaultBranch=main "$@"; }

SRC="$TMP/src"; mkdir -p "$SRC/react"
printf -- '---\nname: react\ndescription: v1.\n---\n# React v1\n' >"$SRC/react/SKILL.md"
git_c init -q "$SRC"; git_c -C "$SRC" add -A; git_c -C "$SRC" commit -qm v1

SOURCES="$TMP/sources.tsv"; printf 'mysrc\tfile://%s\tskills-repo\n' "$SRC" >"$SOURCES"
CACHE="$TMP/cache"; CAT="$TMP/catalog.tsv"
bash "$BUILD" --cache "$CACHE" --sources "$SOURCES" --out "$CAT"
PROJ="$TMP/proj"; mkdir -p "$PROJ"; git_c init -q "$PROJ"
bash "$IMPORT" mysrc react --project "$PROJ" --cache "$CACHE" --catalog "$CAT"
old_sha="$(awk -F'\t' '{print $5}' "$PROJ/.claude/skills/.imported.tsv")"

# advance the source
printf -- '---\nname: react\ndescription: v2.\n---\n# React v2\n' >"$SRC/react/SKILL.md"
git_c -C "$SRC" commit -qam v2

# without --force: exit 4, no change
set +e; bash "$UPDATE" react --project "$PROJ" --cache "$CACHE" --sources "$SOURCES" >/dev/null 2>&1; rc=$?; set -e
[ "$rc" = 4 ] || { echo "FAIL: expected exit 4 without force, got $rc"; exit 1; }
grep -q 'React v1' "$PROJ/.claude/skills/react/SKILL.md" || { echo "FAIL: changed without force"; exit 1; }

# with --force: updates content + sha
bash "$UPDATE" react --project "$PROJ" --cache "$CACHE" --sources "$SOURCES" --force
grep -q 'React v2' "$PROJ/.claude/skills/react/SKILL.md" || { echo "FAIL: not updated with force"; exit 1; }
new_sha="$(awk -F'\t' '{print $5}' "$PROJ/.claude/skills/.imported.tsv")"
[ "$new_sha" != "$old_sha" ] || { echo "FAIL: sha not bumped"; exit 1; }
echo "PASS update-imported"
