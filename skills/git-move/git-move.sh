#!/usr/bin/env bash
# git-move.sh — move/rename or delete files & directories while respecting git.
#
#   git-move.sh <src> <dst>          move / rename (git mv if tracked, else mv)
#   git-move.sh --rm <path> [path…]  delete       (git rm if tracked, else rm -rf)
#
# Detection: if the path is tracked by git (`git ls-files --error-unmatch`) and
# we're inside a work tree, use `git mv` / `git rm` so history & the index stay
# consistent; otherwise fall back to plain `mv` / `rm`. Destination parent dirs
# are created automatically. Never commits — staging only.
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage:
  git-move.sh <src> <dst>          move / rename
  git-move.sh --rm <path> [path…]  delete
EOF
  exit 2
}

in_git_tree() { git rev-parse --is-inside-work-tree >/dev/null 2>&1; }
is_tracked()  { git ls-files --error-unmatch -- "$1" >/dev/null 2>&1; }

[ $# -ge 1 ] || usage

if [ "${1:-}" = "--rm" ]; then
  shift
  [ $# -ge 1 ] || usage
  for path in "$@"; do
    if in_git_tree && is_tracked "$path"; then
      git rm -r -- "$path" >/dev/null
      echo "git rm: $path"
    else
      rm -rf -- "$path"
      echo "rm: $path"
    fi
  done
  exit 0
fi

[ $# -eq 2 ] || usage
src="$1"; dst="$2"
[ -e "$src" ] || { echo "error: source does not exist: $src" >&2; exit 1; }

dstdir="$(dirname -- "$dst")"
[ -d "$dstdir" ] || mkdir -p -- "$dstdir"

if in_git_tree && is_tracked "$src"; then
  git mv -- "$src" "$dst"
  echo "git mv: $src -> $dst"
else
  mv -- "$src" "$dst"
  echo "mv: $src -> $dst"
fi
