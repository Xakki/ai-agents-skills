#!/usr/bin/env bash
# Plan, then apply, a reviewed update of one imported skill (see skill_update.py).
#   update-skill.sh <source> <skill> [--project DIR] [--dest DIR] [--cache DIR] [--catalog FILE] [--sources FILE]
#   update-skill.sh <source> <skill> ... --apply --plan-sha256 HASH [--discard-local]
# The plan is read-only. Apply moves the old directory to a backup and never deletes it.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
args=("$@"); has_sources=0
for a in "$@"; do [ "$a" = --sources ] && has_sources=1; done
[ "$has_sources" = 1 ] || args+=(--sources "$SCRIPT_DIR/sources.tsv")
exec python3 -I "$SCRIPT_DIR/skill_update.py" update "${args[@]}"
