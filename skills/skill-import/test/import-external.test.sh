#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; IMPORT="$HERE/../import-skill.sh"
TMP="$(mktemp -d)"; trap 'rm -rf -- "$TMP"' EXIT
mkdir -p "$TMP/proj" "$TMP/cache"; printf 'aw\taws-skills\texternal\thttps://example.invalid/skill\tx\n' > "$TMP/catalog.tsv"
printf 'aw\thttps://example.invalid/hub\thybrid\n' > "$TMP/sources.tsv"
set +e; out="$(bash "$IMPORT" aw aws-skills --project "$TMP/proj" --cache "$TMP/cache" --catalog "$TMP/catalog.tsv" --sources "$TMP/sources.tsv" 2>&1)"; rc=$?; set -e
[ "$rc" != 0 ] && [[ "$out" == *'external URL import is disabled'* ]] || { echo 'FAIL: external import must be refused'; exit 1; }
[ ! -e "$TMP/proj/.agents" ] && [ ! -e "$TMP/cache/external" ] || { echo 'FAIL: external import changed project/cache'; exit 1; }
echo 'PASS external import refused without network'
