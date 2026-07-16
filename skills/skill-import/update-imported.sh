#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$SCRIPT_DIR/build-catalog.sh"; IMPORT="$SCRIPT_DIR/import-skill.sh"

usage() { cat <<EOF
Usage: update-imported.sh [skill|--all] [--project DIR] [--cache DIR] [--catalog FILE] [--sources FILE] [--force]
Re-sync imported skills from their sources. Without --force, only reports diffs (exit 4 if any).
EOF
}

CACHE="${SKILL_IMPORT_CACHE:-$HOME/.cache/skill-import}"
PROJECT="$PWD"; CATALOG=""; SOURCES="$SCRIPT_DIR/sources.tsv"; FORCE=0; TARGET="--all"
while [ $# -gt 0 ]; do
  case "$1" in
    --all) TARGET="--all";;
    --force) FORCE=1;;
    --project) PROJECT="$2"; shift;;
    --cache) CACHE="$2"; shift;;
    --catalog) CATALOG="$2"; shift;;
    --sources) SOURCES="$2"; shift;;
    -h|--help) usage; exit 0;;
    -*) echo "unknown arg: $1" >&2; usage >&2; exit 2;;
    *) TARGET="$1";;
  esac
  shift
done
[ -n "$CATALOG" ] || CATALOG="$CACHE/catalog.tsv"
man="$PROJECT/.claude/skills/.imported.tsv"
[ -f "$man" ] || { echo "no manifest: $man" >&2; exit 1; }

# refresh sources + rebuild catalog so cache/catalog reflect latest
bash "$BUILD" --cache "$CACHE" --sources "$SOURCES" --out "$CATALOG" >/dev/null

changed=0
while IFS=$'\t' read -r skill source url location sha date; do
  case "$skill" in ''|\#*) continue;; esac
  [ "$TARGET" = "--all" ] || [ "$TARGET" = "$skill" ] || continue
  dest="$PROJECT/.claude/skills/$skill"
  # resolve current source dir from catalog
  row="$(awk -F'\t' -v s="$source" -v k="$skill" '$1==s && $2==k {print; exit}' "$CATALOG")"
  [ -n "$row" ] || { echo "warn: $source/$skill no longer in catalog" >&2; continue; }
  IFS=$'\t' read -r _ _ kind loc _ <<<"$row"
  if [ "$kind" = external ]; then
    if [ "$FORCE" != 1 ]; then
      echo "external $skill ($source): re-pull only with --force (cannot diff locally)"
      continue
    fi
    bash "$IMPORT" "$source" "$skill" --project "$PROJECT" --cache "$CACHE" --catalog "$CATALOG" --force
    continue
  fi
  if [ "$kind" = local ]; then srcdir="$CACHE/repos/$source/$loc"; else srcdir=""; fi
  if [ -n "$srcdir" ] && [ -d "$srcdir" ] && diff -rq "$srcdir" "$dest" >/dev/null 2>&1; then
    continue   # identical, nothing to do
  fi
  changed=1
  if [ "$FORCE" != 1 ]; then
    echo "DIFF $skill ($source): project copy differs from source"
    [ -n "$srcdir" ] && diff -rq "$srcdir" "$dest" 2>/dev/null || true
  else
    bash "$IMPORT" "$source" "$skill" --project "$PROJECT" --cache "$CACHE" --catalog "$CATALOG" --force
  fi
done < "$man"

if [ "$FORCE" != 1 ] && [ "$changed" = 1 ]; then
  echo "run with --force to apply updates" >&2; exit 4
fi
echo "update complete"
