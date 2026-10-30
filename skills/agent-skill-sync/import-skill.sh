#!/usr/bin/env bash
# Import one reviewed, tracked skill from a previously prepared Git cache.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
usage() { cat <<'USAGE'
Usage: import-skill.sh <source> <skill> [--project DIR] [--dest DIR] [--cache DIR] [--catalog FILE] [--sources FILE]
Import only an exact local catalog entry from a clean, origin-verified cache.
The destination must not exist; a provenance receipt is written inside it; no manifest or Git index is modified.
USAGE
}
CACHE="${SKILL_IMPORT_CACHE:-${HOME:?HOME must be set}/.cache/skill-import}"
PROJECT="$PWD"; DEST="${SKILL_IMPORT_DEST:-.agents/skills}"; CATALOG=""; SOURCES="$SCRIPT_DIR/sources.tsv"; SOURCE=""; SKILL=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --force) echo 'skill-import: --force replacement is disabled; plan a reviewed replacement with update-skill.sh' >&2; exit 3;;
    --project|--dest|--cache|--catalog|--sources)
      [ "$#" -ge 2 ] || { usage >&2; exit 2; }; key="$1"; val="$2"; shift
      case "$key" in --project) PROJECT="$val";; --dest) DEST="$val";; --cache) CACHE="$val";; --catalog) CATALOG="$val";; --sources) SOURCES="$val";; esac;;
    -h|--help) usage; exit 0;;
    -*) echo "skill-import: unknown option: $1" >&2; exit 2;;
    *) if [ -z "$SOURCE" ]; then SOURCE="$1"; elif [ -z "$SKILL" ]; then SKILL="$1"; else usage >&2; exit 2; fi;;
  esac
  shift
done
[[ "$SOURCE" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ && "$SOURCE" != *..* ]] || { echo 'skill-import: invalid source name' >&2; exit 5; }
[[ "$SKILL" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ && "$SKILL" != *..* ]] || { echo 'skill-import: invalid skill name' >&2; exit 5; }
[ -n "$CATALOG" ] || CATALOG="$CACHE/catalog.tsv"
[ -f "$CATALOG" ] && [ ! -L "$CATALOG" ] && [ -f "$SOURCES" ] && [ ! -L "$SOURCES" ] || { echo 'skill-import: catalog or sources file unavailable or symlinked' >&2; exit 1; }
PROJECT="$(realpath -e -- "$PROJECT")"
[ -d "$PROJECT" ] || { echo 'skill-import: project is not a directory' >&2; exit 1; }
# Reject ambiguous catalog/source names instead of silently taking the first row.
[ "$(awk -F '\t' -v s="$SOURCE" -v k="$SKILL" '$1==s && $2==k {n++} END {print n+0}' "$CATALOG")" = 1 ] || { echo 'skill-import: catalog entry missing or ambiguous' >&2; exit 1; }
row="$(awk -F '\t' -v s="$SOURCE" -v k="$SKILL" '$1==s && $2==k {print}' "$CATALOG")"
IFS=$'\t' read -r c_source c_skill c_kind c_loc c_desc <<<"$row"
[ "$c_kind" = local ] || { echo 'skill-import: external URL import is disabled; prepare and review a local source cache first' >&2; exit 1; }
[[ "$c_loc" =~ ^[A-Za-z0-9._/-]+$ ]] || { echo 'skill-import: unsupported source location' >&2; exit 5; }
case "$c_loc" in ''|/*|*..*) echo 'skill-import: unsafe source location' >&2; exit 5;; esac
[ "$(awk -F '\t' -v s="$SOURCE" '$1 !~ /^#/ && $1==s {n++} END {print n+0}' "$SOURCES")" = 1 ] || { echo 'skill-import: source configuration missing or ambiguous' >&2; exit 1; }
expected_origin="$(awk -F '\t' -v s="$SOURCE" '$1 !~ /^#/ && $1==s {print $2}' "$SOURCES")"
clone="$CACHE/repos/$SOURCE"
python3 - "$CACHE" <<'PY'
from pathlib import Path
import sys
cache=Path(sys.argv[1]).absolute()
for part in (cache, *cache.parents):
    if part.is_symlink(): raise SystemExit('skill-import: cache path contains a symlink')
if (cache/'repos').is_symlink(): raise SystemExit('skill-import: cache repositories path is a symlink')
PY
[ -d "$clone/.git" ] && [ ! -L "$clone" ] && [ ! -L "$clone/.git" ] || { echo 'skill-import: source cache missing or symlinked' >&2; exit 1; }
actual_origin="$(git -C "$clone" config --get-all remote.origin.url 2>/dev/null || true)"
[ -n "$expected_origin" ] && [ "$actual_origin" = "$expected_origin" ] || { echo 'skill-import: source origin does not match configured provenance' >&2; exit 1; }
sha="$(git -C "$clone" rev-parse --verify 'HEAD^{commit}')"
# Refuse modified tracked source content: the archived bytes must be the reviewed HEAD.
git -C "$clone" diff --quiet HEAD -- "$c_loc" || { echo 'skill-import: source has modified tracked files' >&2; exit 1; }
# Destination is project-contained and has no symlinked path components.
SKILLS_ROOT="$(python3 - "$PROJECT" "$DEST" <<'PY'
import os, pathlib, sys
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
dest="$SKILLS_ROOT/$SKILL"
[ ! -e "$dest" ] && [ ! -L "$dest" ] || { echo 'skill-import: destination exists; refusing to overwrite' >&2; exit 3; }
mkdir -p -- "$SKILLS_ROOT"
stage="$(mktemp -d "$SKILLS_ROOT/.skill-import.XXXXXXXX")"
trap 'rm -rf -- "$stage"' EXIT
# Validate every archived entry and disallow symlinks, submodules and nested Git metadata.
git -C "$clone" ls-tree -rz "$sha" -- "$c_loc" > "$stage/.entries"
python3 - "$stage/.entries" <<'PY'
from pathlib import PurePosixPath
import sys
raw=open(sys.argv[1],'rb').read()
if not raw: raise SystemExit('skill-import: no tracked files at source location')
for item in raw.split(b'\0'):
    if not item: continue
    meta,name=item.split(b'\t',1); mode=meta.split(b' ',1)[0]
    parts=PurePosixPath(name.decode('utf-8','strict')).parts
    if mode not in (b'100644',b'100755') or not parts or any(x in ('.git','..') for x in parts) or any(ord(c)<32 for c in name.decode()):
        raise SystemExit('skill-import: unsafe or unsupported source entry')
PY
rm -- "$stage/.entries"
git -C "$clone" archive "$sha" -- "$c_loc" | tar -xf - -C "$stage"
[ -f "$stage/$c_loc/SKILL.md" ] && [ ! -L "$stage/$c_loc/SKILL.md" ] || { echo 'skill-import: exact source has no regular SKILL.md' >&2; exit 1; }
python3 - "$stage/$c_loc/SKILL.md" "$SKILL" <<'PY'
from pathlib import Path
import re,sys
text=Path(sys.argv[1]).read_text(encoding='utf-8')
match=re.match(r'^---\s*\n(.*?)\n---(?:\s*\n|$)',text,re.S)
names=re.findall(r'^name:\s*([^\n]+)\s*$',match.group(1),re.M) if match else []
if len(names)!=1 or names[0].strip().strip("\"'") != sys.argv[2]:
    raise SystemExit('skill-import: declared skill name does not match selected catalog entry')
PY
# GNU mv no-clobber; check source remains to detect its zero-exit collision case.
source_dir="$stage/$c_loc"
if [ "$c_loc" = . ]; then
  # An existing child is needed so the exclusive staging directory remains ours.
  mkdir -- "$stage/.payload"; find "$stage" -mindepth 1 -maxdepth 1 ! -name .payload -exec mv -t "$stage/.payload" -- {} +
  source_dir="$stage/.payload"
fi
python3 -I "$SCRIPT_DIR/skill_update.py" write-receipt "$source_dir" --source "$SOURCE" --skill "$SKILL" \
  --location "$c_loc" --origin "$expected_origin" --commit "$sha"
mv -T -n -- "$source_dir" "$dest"
[ ! -e "$source_dir" ] || { echo 'skill-import: destination appeared concurrently; no replacement performed' >&2; exit 3; }
printf 'imported %s/%s from commit %s to %s\n' "$SOURCE" "$SKILL" "$sha" "$dest"
printf '%s\n' 'Provenance receipt written inside the skill directory (.skill-import.json); no manifest or Git index was changed.'
