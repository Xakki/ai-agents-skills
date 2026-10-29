#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; UPDATE="$HERE/../update-imported.sh"
TMP="$(mktemp -d)"; trap 'rm -rf -- "$TMP"' EXIT
mkdir -p "$TMP/proj/.agents/skills" "$TMP/cache"; printf 'demo\taw\turl\tpath\tid\tdate\n' > "$TMP/proj/.agents/skills/.imported.tsv"
printf 'aw\tdemo\texternal\thttps://example.invalid/skill\tx\n' > "$TMP/catalog.tsv"; printf 'aw\thttps://example.invalid/hub\thybrid\n' > "$TMP/sources.tsv"
cp "$TMP/proj/.agents/skills/.imported.tsv" "$TMP/original"
for args in '' '--force'; do
 set +e; bash "$UPDATE" --project "$TMP/proj" --cache "$TMP/cache" --catalog "$TMP/catalog.tsv" --sources "$TMP/sources.tsv" $args >/dev/null 2>&1; rc=$?; set -e
 [ "$rc" != 0 ] || { echo 'FAIL: external update must be refused'; exit 1; }
 cmp "$TMP/original" "$TMP/proj/.agents/skills/.imported.tsv" || { echo 'FAIL: manifest changed'; exit 1; }
done
echo 'PASS external updates refused without network'
