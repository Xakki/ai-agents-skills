#!/usr/bin/env bash
# exitcodes.test.sh — the documented exit-code contract (scripts.md):
#   0 success | 1 usage error | 2 validation/not-found | 3 lock contention.
# Spot-checks one case of each across the five scripts.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S="$HERE/../scripts"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
git_c() { git -c user.email=t@t -c user.name=t -c init.defaultBranch=main "$@"; }

REPO="$TMP/myrepo"
mkdir -p "$REPO"; git_c -C "$REPO" init -q
export KANBAN_PREFIX_REGISTRY="$TMP/registry.tsv"

check_rc() {
  local desc="$1" expected="$2"; shift 2
  set +e
  "$@" >/tmp/exitcodes-out.$$ 2>&1
  local rc=$?
  set -e
  [ "$rc" -eq "$expected" ] || { echo "FAIL: $desc — expected exit $expected, got $rc"; cat /tmp/exitcodes-out.$$; rm -f /tmp/exitcodes-out.$$; exit 1; }
  rm -f /tmp/exitcodes-out.$$
}

# --- 1: usage errors (bad/missing flags or args) -----------------------------

check_rc "kanban-id.sh: missing subcommand" 1 bash "$S/kanban-id.sh" --repo "$REPO"
check_rc "kanban-id.sh: unknown subcommand" 1 bash "$S/kanban-id.sh" --repo "$REPO" bogus
check_rc "kanban-new.sh: missing --title" 1 bash "$S/kanban-new.sh" --repo "$REPO"
check_rc "kanban-move.sh: missing args" 1 bash "$S/kanban-move.sh" --repo "$REPO"
check_rc "kanban-status.sh: unknown arg" 1 bash "$S/kanban-status.sh" --repo "$REPO" --bogus

# --- 2: validation / not-found errors ----------------------------------------

check_rc "kanban-id.sh sub: epic not found" 2 bash "$S/kanban-id.sh" --repo "$REPO" sub K-999
check_rc "kanban-new.sh: --sub of missing epic" 2 bash "$S/kanban-new.sh" --repo "$REPO" --title "x" --sub K-999
bash "$S/kanban-new.sh" --repo "$REPO" --title "Move me" --stage todo --prefix K >/dev/null
check_rc "kanban-move.sh: done without --approved" 2 bash "$S/kanban-move.sh" --repo "$REPO" K-001 done --force
check_rc "kanban-move.sh: unknown target stage" 2 bash "$S/kanban-move.sh" --repo "$REPO" K-001 nowhere

# --- 2: kanban-lint.sh findings present --------------------------------------

mkdir -p "$REPO/.claude/kanban/todo"
cat > "$REPO/.claude/kanban/todo/K-777-broken.md" <<'EOF'
no title, no sections
EOF
check_rc "kanban-lint.sh: findings present" 2 bash "$S/kanban-lint.sh" --repo "$REPO"
rm -f "$REPO/.claude/kanban/todo/K-777-broken.md"

# --- 3: lock contention (flock timeout) --------------------------------------

# kanban-id.sh flocks a stable companion file ("<lockfile>.flock"), NOT
# kanban.lock itself — kanban.lock is replaced via mktemp+mv on every write
# (lock_upsert), so flock-ing it directly would be a TOCTOU (a waiter on the
# old inode is disconnected from whoever opens the new one after a rename).
mkdir -p "$REPO/.claude"
LOCKFILE="$REPO/.claude/kanban.lock"
LOCKMARKER="$LOCKFILE.flock"
: > "$LOCKMARKER"
( flock "$LOCKMARKER" -c 'sleep 3' ) &
HOLDER=$!
# give the holder a moment to actually grab the lock before we contend on it
sleep 0.3
check_rc "kanban-id.sh: lock contention" 3 env KANBAN_LOCK_TIMEOUT_SEC=1 bash "$S/kanban-id.sh" --repo "$REPO" next K
wait "$HOLDER" 2>/dev/null || true

echo "PASS exitcodes"
