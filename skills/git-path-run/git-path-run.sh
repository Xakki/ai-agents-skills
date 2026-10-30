#!/usr/bin/env bash
# Move or remove explicitly selected paths without clobbering local data.
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage:
  git-path-run.sh <src> <dst>
  git-path-run.sh --rm [--recursive] <path> [path…]
--recursive is required for untracked directories; mixed tracked/untracked
Git directories are refused. Operations in a Git repository can stage changes.
USAGE
  exit 2
}
error() { printf 'git-path-run: %s\n' "$*" >&2; exit 1; }
in_git_tree() { git rev-parse --is-inside-work-tree >/dev/null 2>&1; }
is_tracked() { git ls-files --error-unmatch -- ":(literal)$1" >/dev/null 2>&1; }
path_exists() { [ -e "$1" ] || [ -L "$1" ]; }

# Git tracks files, not directories. A tracked directory can also contain
# ignored/untracked files or empty directories, all of which git mv would move.
check_directory_contents() {
  local root="$1" item
  find -- "$root" -mindepth 1 -print0 | while IFS= read -r -d '' item; do
    if [ -d "$item" ] && [ ! -L "$item" ]; then
      git ls-files --error-unmatch -- ":(literal)$item/" >/dev/null 2>&1 ||
        error "directory contains untracked or empty directory: $item"
    else
      is_tracked "$item" || error "directory contains untracked or ignored path: $item"
    fi
  done
}

[ $# -ge 1 ] || usage
if [ "$1" = '--rm' ]; then
  shift
  recursive=false
  if [ "${1:-}" = '--recursive' ]; then recursive=true; shift; fi
  [ $# -ge 1 ] || usage
  cwd_abs="$(pwd -P)"
  paths_abs=()
  # Validate every operand before changing any of them.
  for path in "$@"; do
    path_exists "$path" || error "path does not exist: $path"
    # Resolve intermediate symlinks: lexical normalization alone could let an
    # alias to the working directory bypass the ancestor-removal guard.
    path_abs="$(realpath -m -- "$path")"
    [ "$path_abs" != / ] || error 'refusing to remove filesystem root'
    case "$cwd_abs/" in "$path_abs/"*) error "refusing to remove current directory or an ancestor: $path";; esac
    for previous in "${paths_abs[@]}"; do
      case "$path_abs/" in "$previous/"*) error "overlapping removal paths: $path";; esac
      case "$previous/" in "$path_abs/"*) error "overlapping removal paths: $path";; esac
    done
    paths_abs+=("$path_abs")
    if in_git_tree && is_tracked "$path"; then
      if [ -d "$path" ] && [ ! -L "$path" ]; then check_directory_contents "$path"; fi
      git rm --dry-run -r -- ":(literal)$path" >/dev/null || error "Git refused removal: $path"
    elif [ -d "$path" ] && [ ! -L "$path" ] && [ "$recursive" = false ]; then
      error "untracked directory requires --recursive: $path"
    fi
  done
  for path in "$@"; do
    if in_git_tree && is_tracked "$path"; then
      git rm -r -- ":(literal)$path" >/dev/null
      printf 'git rm: %s\n' "$path"
    elif [ -d "$path" ] && [ ! -L "$path" ]; then
      rm -r -- "$path"
      printf 'rm: %s\n' "$path"
    else
      rm -- "$path"
      printf 'rm: %s\n' "$path"
    fi
  done
  exit 0
fi

[ $# -eq 2 ] || usage
src="$1"; dst="$2"
path_exists "$src" || error "source does not exist: $src"
path_exists "$dst" && error "destination already exists: $dst"
if [ -d "$src" ] && [ ! -L "$src" ]; then
  src_abs="$(realpath -m -- "$src")"
  dst_abs="$(realpath -m -- "$dst")"
  case "$dst_abs/" in "$src_abs/"*) error 'destination is inside source directory';; esac
  if in_git_tree && is_tracked "$src"; then check_directory_contents "$src"; fi
fi
mkdir -p -- "$(dirname -- "$dst")"
if in_git_tree && is_tracked "$src"; then
  git mv -- "$src" "$dst"
  printf 'git mv: %s -> %s\n' "$src" "$dst"
else
  mv -T -n -- "$src" "$dst"
  ! path_exists "$src" || error "move did not complete: $src"
  printf 'mv: %s -> %s\n' "$src" "$dst"
fi
