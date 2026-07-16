#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$HERE/../build-catalog.sh"; IMPORT="$HERE/../import-skill.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
git_c() { git -c user.email=t@t -c user.name=t -c init.defaultBranch=main "$@"; }

# --- 1: build-catalog skips a malicious `name:` and still emits the sibling skill ---
SRC1="$TMP/src1"; mkdir -p "$SRC1/evil" "$SRC1/good"
printf -- '---\nname: ../../../evil\ndescription: Malicious name.\n---\n# Evil\n' >"$SRC1/evil/SKILL.md"
printf -- '---\nname: good\ndescription: A normal sibling skill.\n---\n# Good\n' >"$SRC1/good/SKILL.md"
git_c init -q "$SRC1"; git_c -C "$SRC1" add -A; git_c -C "$SRC1" commit -qm init

SOURCES1="$TMP/sources1.tsv"; printf 'mysrc\tfile://%s\tskills-repo\n' "$SRC1" >"$SOURCES1"
CACHE1="$TMP/cache1"; CAT1="$TMP/catalog1.tsv"
bash "$BUILD" --cache "$CACHE1" --sources "$SOURCES1" --out "$CAT1" 2>/dev/null

grep -q '\.\./' "$CAT1" && { echo "FAIL: catalog contains a traversal row"; cat "$CAT1"; exit 1; }
grep -qP '^mysrc\tgood\tlocal\t' "$CAT1" || { echo "FAIL: sibling skill missing from catalog"; cat "$CAT1"; exit 1; }
echo "PASS security: build-catalog skips malicious name"

# --- 2: import-skill.sh rejects a traversal skill argument, exit 5, nothing written outside the project ---
CACHE2="$TMP/cache2"; mkdir -p "$CACHE2"
CAT2="$TMP/catalog2.tsv"
printf 'source\tskill\tkind\tlocation\tdescription\n' >"$CAT2"
printf 'mysrc\t../evil\tlocal\t.\tShould never be used.\n' >>"$CAT2"

PROJ2="$TMP/proj2"; mkdir -p "$PROJ2"; git_c init -q "$PROJ2"
set +e; bash "$IMPORT" mysrc '../evil' --project "$PROJ2" --cache "$CACHE2" --catalog "$CAT2" >/dev/null 2>&1; rc=$?; set -e
[ "$rc" = 5 ] || { echo "FAIL: expected exit 5 for traversal skill arg, got $rc"; exit 1; }
[ ! -e "$PROJ2/.claude/skills/../evil" ] || { echo "FAIL: traversal target was created"; exit 1; }
[ ! -e "$PROJ2/.claude/evil" ] || { echo "FAIL: traversal escaped into .claude/"; exit 1; }
echo "PASS security: import-skill rejects traversal skill arg"

# --- 3: root-level SKILL.md gets location '.' (not the absolute clone path) ---
SRC3="$TMP/src3"; mkdir -p "$SRC3"
printf -- '---\nname: root-skill\ndescription: Lives at repo root.\n---\n# Root\n' >"$SRC3/SKILL.md"
git_c init -q "$SRC3"; git_c -C "$SRC3" add -A; git_c -C "$SRC3" commit -qm init

SOURCES3="$TMP/sources3.tsv"; printf 'rootsrc\tfile://%s\tskills-repo\n' "$SRC3" >"$SOURCES3"
CACHE3="$TMP/cache3"; CAT3="$TMP/catalog3.tsv"
bash "$BUILD" --cache "$CACHE3" --sources "$SOURCES3" --out "$CAT3"

grep -qP '^rootsrc\troot-skill\tlocal\t\.\t' "$CAT3" || { echo "FAIL: root-level location is not '.'"; cat "$CAT3"; exit 1; }
echo "PASS security: root-level SKILL.md location is '.'"

echo "PASS security"
