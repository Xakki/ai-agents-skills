#!/usr/bin/env bash
# Read-only comparison of legacy imported-skill records. No network or mutation.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
usage() { cat <<'USAGE'
Usage: update-imported.sh [skill|--all] [--project DIR] [--dest DIR] [--cache DIR] [--catalog FILE] [--sources FILE] [--manifest FILE]
Report differences using an existing local catalog and manifest. Never overwrite files.
USAGE
}
CACHE="${SKILL_IMPORT_CACHE:-${HOME:?HOME must be set}/.cache/skill-import}"; PROJECT="$PWD"; DEST="${SKILL_IMPORT_DEST:-.agents/skills}"; CATALOG=""; SOURCES="$SCRIPT_DIR/sources.tsv"; MANIFEST=""; TARGET="--all"
while [ "$#" -gt 0 ]; do
 case "$1" in
  --force) echo 'skill-import: automatic replacement is disabled; plan a reviewed replacement with update-skill.sh' >&2; exit 3;;
  --all) TARGET=--all;;
  --project|--dest|--cache|--catalog|--sources|--manifest)
   [ "$#" -ge 2 ] || { usage >&2; exit 2; };key="$1";val="$2";shift
   case "$key" in --project) PROJECT="$val";; --dest) DEST="$val";; --cache) CACHE="$val";; --catalog) CATALOG="$val";; --sources) SOURCES="$val";; --manifest) MANIFEST="$val";; esac;;
  -h|--help) usage;exit 0;;
  -*) echo 'skill-import: unknown option' >&2;exit 2;;
  *) TARGET="$1";;
 esac;shift
done
PROJECT="$(realpath -e -- "$PROJECT")"
SKILLS_ROOT="$(python3 - "$PROJECT" "$DEST" <<'PY'
import os,pathlib,sys
project=pathlib.Path(sys.argv[1]); raw=pathlib.Path(sys.argv[2]); dest=pathlib.Path(os.path.abspath(raw if raw.is_absolute() else project/raw))
try: relative=dest.relative_to(project)
except ValueError: raise SystemExit('skill-import: destination is outside the project')
if not relative.parts: raise SystemExit('skill-import: destination cannot be the project root')
current=project
for part in relative.parts:
    current=current/part
    if current.is_symlink(): raise SystemExit('skill-import: destination path contains a symlink')
print(dest)
PY
)"
[ -n "$CATALOG" ] || CATALOG="$CACHE/catalog.tsv"
[ -n "$MANIFEST" ] || MANIFEST="$SKILLS_ROOT/.imported.tsv"
for file in "$MANIFEST" "$CATALOG" "$SOURCES"; do [ -f "$file" ] && [ ! -L "$file" ] || { echo 'skill-import: manifest, catalog or sources file missing or symlinked' >&2;exit 1; };done
python3 - "$CACHE" <<'PY'
from pathlib import Path
import sys
cache=Path(sys.argv[1]).absolute()
for part in (cache, *cache.parents):
    if part.is_symlink(): raise SystemExit('skill-import: cache path contains a symlink')
if (cache/'repos').is_symlink(): raise SystemExit('skill-import: cache repositories path is a symlink')
PY
tmp="$(mktemp -d "${TMPDIR:-/tmp}/skill-import-preview.XXXXXXXX")"
trap 'rm -rf -- "$tmp"' EXIT
changed=0;found=0
while IFS=$'\t' read -r skill source url location sha date; do
 case "$skill" in ''|\#*) continue;; esac
 [ "$TARGET" = --all ] || [ "$TARGET" = "$skill" ] || continue
 found=1
 [[ "$skill" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ && "$skill" != *..* && "$source" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ && "$source" != *..* ]] || { echo 'skill-import: unsafe manifest component' >&2; exit 5; }
 [ "$(awk -F '\t' -v s="$source" -v k="$skill" '$1==s && $2==k {n++} END{print n+0}' "$CATALOG")" = 1 ] || { echo "skill-import: catalog entry missing or ambiguous: $skill" >&2;exit 1; }
 row="$(awk -F '\t' -v s="$source" -v k="$skill" '$1==s && $2==k {print}' "$CATALOG")"
 IFS=$'\t' read -r _ _ kind loc _ <<<"$row"
 [ "$kind" = local ] || { echo "skill-import: external source cannot be verified offline: $skill" >&2;exit 1; }
 [[ "$loc" =~ ^[A-Za-z0-9._/-]+$ ]] || { echo 'skill-import: unsupported source path' >&2;exit 5; }
 case "$loc" in ''|/*|*..*) echo 'skill-import: unsafe source path' >&2;exit 5;; esac
 clone="$CACHE/repos/$source"; dest="$SKILLS_ROOT/$skill"
 [ ! -L "$clone" ] && [ ! -L "$clone/.git" ] && [ ! -L "$dest" ] || { echo 'skill-import: symlinked source or destination refused' >&2;exit 1; }
 [ -d "$clone/.git" ] && [ -d "$dest" ] || { echo "skill-import: source or destination absent: $skill" >&2;exit 1; }
 expected="$(awk -F '\t' -v s="$source" '$1 !~ /^#/ && $1==s {print $2}' "$SOURCES")"
 actual="$(git -C "$clone" config --get-all remote.origin.url 2>/dev/null || true)"
 [ -n "$expected" ] && [ "$expected" = "$actual" ] || { echo 'skill-import: unverifiable source origin' >&2;exit 1; }
 clone_real="$(realpath -e -- "$clone")"; src="$(realpath -e -- "$clone/$loc")"
 case "$src" in "$clone_real"|"$clone_real"/*) :;; *) echo 'skill-import: source resolves outside cache' >&2;exit 1;; esac
 find "$dest" -type l -print -quit > "$tmp/symlink-check" || { echo 'skill-import: destination tree cannot be inspected' >&2;exit 1; }
 [ ! -s "$tmp/symlink-check" ] || { echo 'skill-import: symlinked destination tree refused' >&2;exit 1; }
 git -C "$clone" diff --quiet HEAD -- "$loc" || { echo 'skill-import: tracked source changes cannot be compared safely' >&2;exit 1; }
 entry_dir="$(mktemp -d "$tmp/source.XXXXXXXX")"
 git -C "$clone" ls-tree -rz HEAD -- "$loc" > "$entry_dir/.entries"
 python3 - "$entry_dir/.entries" <<'PY'
from pathlib import PurePosixPath
import sys
raw=open(sys.argv[1],'rb').read()
if not raw: raise SystemExit('skill-import: no tracked source entries')
for item in raw.split(b'\0'):
    if not item: continue
    meta,name=item.split(b'\t',1); mode=meta.split(b' ',1)[0]
    value=name.decode('utf-8','strict'); parts=PurePosixPath(value).parts
    if mode not in (b'100644',b'100755') or not parts or any(x in ('.git','..') for x in parts) or any(ord(c)<32 for c in value):
        raise SystemExit('skill-import: unsafe or unsupported source entry')
PY
 rm -- "$entry_dir/.entries"
 git -C "$clone" archive HEAD -- "$loc" | tar -xf - -C "$entry_dir"
 [ -f "$entry_dir/$loc/SKILL.md" ] || { echo 'skill-import: source has no regular SKILL.md' >&2;exit 1; }
 if diff -rq -x .skill-import.json "$entry_dir/$loc" "$dest" >/dev/null 2>&1;then echo "UNCHANGED $skill";else echo "DIFF $skill: manual review required";changed=1;fi
done < "$MANIFEST"
[ "$found" = 1 ] || { echo 'skill-import: target not in manifest' >&2;exit 1; }
[ "$changed" = 0 ] || exit 4
