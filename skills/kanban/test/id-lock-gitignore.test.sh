#!/usr/bin/env bash
# id-lock-gitignore.test.sh — the transient lock artifacts (kanban.lock.flock,
# and the mkdir-spinlock fallback kanban.lock.lockdir) must never show up as
# untracked/dirty in the user's repo: the first lock acquisition idempotently
# ensures .claude/.gitignore excludes them, without ever rewriting or
# duplicating whatever's already there.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KID="$HERE/../scripts/kanban-id.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
git_c() { git -c user.email=t@t -c user.name=t -c init.defaultBranch=main "$@"; }

REPO="$TMP/myrepo"
mkdir -p "$REPO"; git_c -C "$REPO" init -q
export KANBAN_PREFIX_REGISTRY="$TMP/registry.tsv"

bash "$KID" --repo "$REPO" set-prefix K >/dev/null
bash "$KID" --repo "$REPO" next >/dev/null

GI="$REPO/.claude/.gitignore"
[ -f "$GI" ] || { echo "FAIL: .claude/.gitignore was not created"; exit 1; }
grep -qxF "/kanban.lock.flock" "$GI" || { echo "FAIL: missing /kanban.lock.flock entry"; cat "$GI"; exit 1; }
grep -qxF "/kanban.lock.lockdir" "$GI" || { echo "FAIL: missing /kanban.lock.lockdir entry"; cat "$GI"; exit 1; }

git_c -C "$REPO" add .claude/.gitignore .claude/kanban.lock
STATUS="$(git_c -C "$REPO" status --short)"
printf '%s\n' "$STATUS" | grep -q 'flock' && { echo "FAIL: git status still shows the .flock artifact"; echo "$STATUS"; exit 1; }
printf '%s\n' "$STATUS" | grep -q 'lockdir' && { echo "FAIL: git status still shows the .lockdir artifact"; echo "$STATUS"; exit 1; }

git_c -C "$REPO" check-ignore -q .claude/kanban.lock.flock \
  || { echo "FAIL: kanban.lock.flock is not actually ignored"; exit 1; }

# a pre-existing .gitignore with unrelated content must be preserved verbatim,
# with only the missing entries appended — never rewritten or reordered.
REPO2="$TMP/myrepo2"
mkdir -p "$REPO2/.claude"; git_c -C "$REPO2" init -q
printf '%s\n' "node_modules/" "*.log" > "$REPO2/.claude/.gitignore"
bash "$KID" --repo "$REPO2" set-prefix K >/dev/null
bash "$KID" --repo "$REPO2" next >/dev/null
GI2="$REPO2/.claude/.gitignore"
[ "$(sed -n '1p' "$GI2")" = "node_modules/" ] || { echo "FAIL: pre-existing first line was disturbed"; cat "$GI2"; exit 1; }
[ "$(sed -n '2p' "$GI2")" = "*.log" ] || { echo "FAIL: pre-existing second line was disturbed"; cat "$GI2"; exit 1; }
grep -qxF "/kanban.lock.flock" "$GI2" || { echo "FAIL: entry not appended to existing gitignore"; cat "$GI2"; exit 1; }

# running allocations again must not duplicate the lines
bash "$KID" --repo "$REPO2" next >/dev/null
bash "$KID" --repo "$REPO2" next >/dev/null
COUNT="$(grep -cxF "/kanban.lock.flock" "$GI2")"
[ "$COUNT" -eq 1 ] || { echo "FAIL: expected exactly 1 occurrence of /kanban.lock.flock after repeated runs, got $COUNT"; cat "$GI2"; exit 1; }

echo "PASS id-lock-gitignore"
