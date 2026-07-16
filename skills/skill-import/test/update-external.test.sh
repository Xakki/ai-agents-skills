#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$HERE/../build-catalog.sh"; IMPORT="$HERE/../import-skill.sh"; UPDATE="$HERE/../update-imported.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
git_c() { git -c user.email=t@t -c user.name=t -c init.defaultBranch=main "$@"; }

# external fixture repo (v1), fetched later via a pre-seeded cache clone whose
# origin points here -- no real network / github.com access needed.
EXT="$TMP/ext"; mkdir -p "$EXT"
printf -- '---\nname: aws-skills\ndescription: v1.\n---\n# AWS v1\n' >"$EXT/SKILL.md"
git_c init -q "$EXT"; git_c -C "$EXT" add -A; git_c -C "$EXT" commit -qm v1

# hub repo: a hybrid-type source whose README references a github.com-shaped
# URL. build-catalog.sh only ever *parses* this URL out of the README (it
# never fetches it), so the URL can be fictitious.
HUB="$TMP/hub"; mkdir -p "$HUB"
cat >"$HUB/README.md" <<'EOF'
# Hub
- [AWS Skills](https://github.com/fakeorg/aws-skills) — external test skill.
EOF
git_c init -q "$HUB"; git_c -C "$HUB" add -A; git_c -C "$HUB" commit -qm init

SOURCES="$TMP/sources.tsv"; printf 'hub\tfile://%s\thybrid\n' "$HUB" >"$SOURCES"
CACHE="$TMP/cache"; CAT="$CACHE/catalog.tsv"
bash "$BUILD" --cache "$CACHE" --sources "$SOURCES" --out "$CAT"
grep -qP '^hub\taws-skills\texternal\thttps://github\.com/fakeorg/aws-skills\t' "$CAT" \
  || { echo "FAIL: external row missing from built catalog"; cat "$CAT"; exit 1; }

# pre-seed the external cache clone slug ("aws-skills", derived from the
# github.com URL's basename) so import-skill.sh's real "git clone" branch is
# never taken; its origin points at our local EXT fixture, so the fetch/reset
# branch (Part B fix) pulls from EXT instead of the real internet.
mkdir -p "$CACHE/external"
git_c clone -q "$EXT" "$CACHE/external/aws-skills"

PROJ="$TMP/proj"; mkdir -p "$PROJ"; git_c init -q "$PROJ"
bash "$IMPORT" hub aws-skills --project "$PROJ" --cache "$CACHE" --catalog "$CAT"
grep -q 'AWS v1' "$PROJ/.claude/skills/aws-skills/SKILL.md" || { echo "FAIL: initial external import"; exit 1; }
old_sha="$(awk -F'\t' '{print $5}' "$PROJ/.claude/skills/.imported.tsv")"

# advance the external fixture
printf -- '---\nname: aws-skills\ndescription: v2.\n---\n# AWS v2\n' >"$EXT/SKILL.md"
git_c -C "$EXT" commit -qam v2

# without --force: exit 0 (NOT 4 -- external can't be diffed locally),
# project copy untouched, honest note on stdout.
set +e
out="$(bash "$UPDATE" aws-skills --project "$PROJ" --cache "$CACHE" --sources "$SOURCES" 2>&1)"; rc=$?
set -e
[ "$rc" = 0 ] || { echo "FAIL: expected exit 0 without force for external, got $rc"; echo "$out"; exit 1; }
printf '%s\n' "$out" | grep -q 're-pull only with --force' || { echo "FAIL: missing honest note"; echo "$out"; exit 1; }
grep -q 'AWS v1' "$PROJ/.claude/skills/aws-skills/SKILL.md" || { echo "FAIL: changed without force"; exit 1; }

# with --force: re-pulls latest (v2) via the fetch/reset path
bash "$UPDATE" aws-skills --project "$PROJ" --cache "$CACHE" --sources "$SOURCES" --force
grep -q 'AWS v2' "$PROJ/.claude/skills/aws-skills/SKILL.md" || { echo "FAIL: not updated with force"; exit 1; }
new_sha="$(awk -F'\t' '{print $5}' "$PROJ/.claude/skills/.imported.tsv")"
[ "$new_sha" != "$old_sha" ] || { echo "FAIL: sha not bumped"; exit 1; }

echo "PASS update-external"
