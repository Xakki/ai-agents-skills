#!/usr/bin/env bash
# stages.test.sh — freeze is resumable; closed is a terminal approved cancellation.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KNEW="$HERE/../scripts/kanban-new.sh"
KMOVE="$HERE/../scripts/kanban-move.sh"
KLINT="$HERE/../scripts/kanban-lint.sh"
KSTATUS="$HERE/../scripts/kanban-status.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1" >&2; exit 1; }
git_c() { git -c user.email=t@t -c user.name=t -c init.defaultBranch=main "$@"; }

REPO="$TMP/stages"
mkdir -p "$REPO"
git_c -C "$REPO" init -q
mkdir -p "$REPO/.agents"
printf 'prefix=K\nK=99\n' > "$REPO/.agents/kanban.lock"
export KANBAN_PREFIX_REGISTRY="$TMP/registry.tsv"
MOVE_HELP="$(bash "$KMOVE" --help)"
printf '%s\n' "$MOVE_HELP" | grep -q -- '--resume' \
  || fail "kanban-move help does not document --resume"
new_card() {
  local stage="$1" id="$2" title="$3" path
  mkdir -p "$REPO/.agents/kanban/$stage"
  path="$REPO/.agents/kanban/$stage/$id-$title.md"
  printf '### %s\n\n**Criticality:** Medium\n**TAGS:**\n**Description:**\n**Problem:**\n**Impact:**\n**Recommendation:**\n**Acceptance Criteria:**\n' "$title" > "$path"
  printf '%s\n' "$path"
}
expect_rejected() {
  local label="$1"; shift
  local output rc
  set +e
  output="$(bash "$KMOVE" --repo "$REPO" "$@" 2>&1)"
  rc=$?
  set -e
  [ "$rc" -eq 2 ] || fail "$label should be rejected with exit 2, got $rc: $output"
}

PAUSE="$(new_card todo K-001 pause)"
MOVED="$(bash "$KMOVE" --repo "$REPO" K-001 freeze)"
[ "$MOVED" = "$REPO/.agents/kanban/freeze/K-001-pause.md" ] \
  || fail "active card did not enter freeze"
expect_rejected "resume without --resume" K-001 progress
[ -f "$REPO/.agents/kanban/freeze/K-001-pause.md" ] \
  || fail "rejected implicit resume moved the frozen card"
MOVED="$(bash "$KMOVE" --repo "$REPO" K-001 progress --resume)"
[ "$MOVED" = "$REPO/.agents/kanban/progress/K-001-pause.md" ] \
  || fail "--resume did not return the card to progress"

CLOSE="$(new_card todo K-002 cancel)"
expect_rejected "close without --approved" K-002 closed
[ -f "$CLOSE" ] || fail "unapproved close moved the card"
bash "$KMOVE" --repo "$REPO" K-002 closed --approved >/dev/null
printf 'incomplete archived note\n' > "$REPO/.agents/kanban/closed/K-002-cancel.md"
expect_rejected "closed terminal stage" K-002 progress --force
[ -f "$REPO/.agents/kanban/closed/K-002-cancel.md" ] \
  || fail "--force moved a card out of closed"

FROZEN="$(new_card freeze K-003 parked-cancel)"
bash "$KMOVE" --repo "$REPO" K-003 closed --approved >/dev/null
printf 'incomplete archived note\n' > "$REPO/.agents/kanban/closed/K-003-parked-cancel.md"

DONE="$(new_card done K-004 completed)"
expect_rejected "successful completion must not become freeze" K-004 freeze --force
[ -f "$DONE" ] || fail "--force moved a completed card into freeze"
expect_rejected "successful completion must not become closed" K-004 closed --approved --force
[ -f "$DONE" ] || fail "--force moved a completed card into closed"

new_card custom K-008 unknown-stage > /dev/null
expect_rejected "unknown source stage must not bypass close rules" K-008 closed --approved --force
expect_rejected "unknown source stage must not bypass freeze rules" K-008 freeze --force
rm -f "$REPO/.agents/kanban/custom/K-008-unknown-stage.md"

new_card freeze K-005 parked > /dev/null
printf 'incomplete parked note\n' > "$REPO/.agents/kanban/freeze/K-005-parked.md"
new_card freeze K-006 resume-todo > /dev/null
bash "$KMOVE" --repo "$REPO" K-006 todo --resume >/dev/null
new_card todo K-007 wrong-resume > /dev/null
expect_rejected "--resume outside freeze" K-007 progress --resume
new_card ready EPIC-010a-01 letter-suffixed-child > /dev/null
expect_rejected "letter-suffixed epic child must wait for its parent" EPIC-010a-01 done --approved
rm -f "$REPO/.agents/kanban/ready/EPIC-010a-01-letter-suffixed-child.md"

STATUS="$(bash "$KSTATUS" --repo "$REPO")"
printf '%s\n' "$STATUS" | grep -q '^freeze (1)$' || fail "status omitted freeze stage"
printf '%s\n' "$STATUS" | grep -q '^closed (2)$' || fail "status omitted closed stage"
FILTERED="$(bash "$KSTATUS" --repo "$REPO" --stage closed)"
printf '%s\n' "$FILTERED" | grep -q 'K-002' \
  || fail "status --stage closed omitted closed cards"

LINT="$(bash "$KLINT" --repo "$REPO" 2>&1)" \
  || fail "active cards should lint while archived cards are excluded: $LINT"
printf '%s\n' "$LINT" | grep -q '^kanban-lint: 3 card(s) checked, 0 error(s), 0 warning(s)$' \
  || fail "unexpected lint scope/count: $LINT"

ALIAS_REPO="$TMP/alias-board"
mkdir -p "$ALIAS_REPO/.agents/kanban/todo"
git_c -C "$ALIAS_REPO" init -q
ln -s .agents "$ALIAS_REPO/.claude"
printf 'alias card\n' > "$ALIAS_REPO/.agents/kanban/todo/K-009-alias-path.md"
git_c -C "$ALIAS_REPO" add .agents/kanban/todo/K-009-alias-path.md
git_c -C "$ALIAS_REPO" commit -qm 'fixture: add alias test card'
ALIAS_OUT="$(bash "$KMOVE" --repo "$ALIAS_REPO" "$ALIAS_REPO/.claude/kanban/todo/K-009-alias-path.md" progress)"
[ "$ALIAS_OUT" = "$ALIAS_REPO/.agents/kanban/progress/K-009-alias-path.md" ] \
  || fail "move through .claude alias did not use physical board root: $ALIAS_OUT"
ALIAS_CACHED="$(git_c -C "$ALIAS_REPO" diff --cached --name-status)"
[ "$ALIAS_CACHED" = $'R100\t.agents/kanban/todo/K-009-alias-path.md\t.agents/kanban/progress/K-009-alias-path.md' ] \
  || fail "move through .claude alias did not stage a canonical rename: $ALIAS_CACHED"

echo "PASS stages"
