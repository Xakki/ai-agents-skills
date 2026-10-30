#!/usr/bin/env bash
# board-root.test.sh — board aliases resolve to one physical root and lock.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../scripts/kanban-lib.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

REPO_LEGACY="$TMP/legacy"
mkdir -p "$REPO_LEGACY/.claude/kanban/todo"
[ "$(kanban::board_dir "$REPO_LEGACY")" = "$REPO_LEGACY/.claude/kanban" ] \
  || { echo "FAIL: legacy .claude board root changed"; exit 1; }
[ "$(kanban::lock_file "$REPO_LEGACY")" = "$REPO_LEGACY/.claude/kanban.lock" ] \
  || { echo "FAIL: legacy lock is not adjacent to its board root"; exit 1; }

REPO_ALIAS="$TMP/alias"
mkdir -p "$REPO_ALIAS/.agents/kanban/todo"
ln -s .agents "$REPO_ALIAS/.claude"
[ "$(kanban::board_dir "$REPO_ALIAS")" = "$REPO_ALIAS/.agents/kanban" ] \
  || { echo "FAIL: .claude alias did not resolve to the physical .agents board"; exit 1; }
[ "$(kanban::lock_file "$REPO_ALIAS")" = "$REPO_ALIAS/.agents/kanban.lock" ] \
  || { echo "FAIL: aliases do not share the .agents lock"; exit 1; }

REPO_EMPTY="$TMP/empty"
mkdir -p "$REPO_EMPTY"
[ "$(kanban::board_dir "$REPO_EMPTY")" = "$REPO_EMPTY/.agents/kanban" ] \
  || { echo "FAIL: new boards do not default to .agents/kanban"; exit 1; }
[ "$(kanban::lock_file "$REPO_EMPTY")" = "$REPO_EMPTY/.agents/kanban.lock" ] \
  || { echo "FAIL: new-board lock does not default to .agents/kanban.lock"; exit 1; }

REPO_LOCK_ONLY="$TMP/legacy-lock-only"
mkdir -p "$REPO_LOCK_ONLY/.claude"
: > "$REPO_LOCK_ONLY/.claude/kanban.lock"
[ "$(kanban::board_dir "$REPO_LOCK_ONLY")" = "$REPO_LOCK_ONLY/.claude/kanban" ] \
  || { echo "FAIL: existing legacy lock was ignored when the board is empty"; exit 1; }
[ "$(kanban::lock_file "$REPO_LOCK_ONLY")" = "$REPO_LOCK_ONLY/.claude/kanban.lock" ] \
  || { echo "FAIL: existing legacy lock moved to a second counter path"; exit 1; }

REPO_AMBIG="$TMP/ambiguous"
mkdir -p "$REPO_AMBIG/.claude/kanban" "$REPO_AMBIG/.agents/kanban"
set +e
OUT="$(kanban::board_dir "$REPO_AMBIG" 2>"$TMP/ambiguous.err")"
RC=$?
set -e
[ "$RC" -ne 0 ] || { echo "FAIL: distinct board roots must be rejected"; exit 1; }
grep -q "both .claude/kanban and .agents/kanban exist" "$TMP/ambiguous.err" \
  || { echo "FAIL: ambiguous-root error is not actionable"; cat "$TMP/ambiguous.err"; exit 1; }
[ -z "$OUT" ] || { echo "FAIL: ambiguous board root was returned: $OUT"; exit 1; }

REPO_LOCK_AMBIG="$TMP/ambiguous-locks"
mkdir -p "$REPO_LOCK_AMBIG/.claude" "$REPO_LOCK_AMBIG/.agents"
: > "$REPO_LOCK_AMBIG/.claude/kanban.lock"
: > "$REPO_LOCK_AMBIG/.agents/kanban.lock"
set +e
OUT="$(kanban::board_dir "$REPO_LOCK_AMBIG" 2>"$TMP/ambiguous-locks.err")"
RC=$?
set -e
[ "$RC" -ne 0 ] || { echo "FAIL: distinct lock files must be rejected"; exit 1; }
grep -q "both .claude/kanban.lock and .agents/kanban.lock exist" "$TMP/ambiguous-locks.err" \
  || { echo "FAIL: ambiguous-lock error is not actionable"; cat "$TMP/ambiguous-locks.err"; exit 1; }

REPO_LOCK_MISMATCH="$TMP/board-lock-mismatch"
mkdir -p "$REPO_LOCK_MISMATCH/.agents/kanban/todo" "$REPO_LOCK_MISMATCH/.claude"
: > "$REPO_LOCK_MISMATCH/.claude/kanban.lock"
set +e
OUT="$(kanban::board_dir "$REPO_LOCK_MISMATCH" 2>"$TMP/board-lock-mismatch.err")"
RC=$?
set -e
[ "$RC" -ne 0 ] || { echo "FAIL: lock outside the resolved board root must be rejected"; exit 1; }
grep -q "lock path conflicts with resolved board root" "$TMP/board-lock-mismatch.err" \
  || { echo "FAIL: mismatched-lock error is not actionable"; cat "$TMP/board-lock-mismatch.err"; exit 1; }

echo "PASS board-root"
