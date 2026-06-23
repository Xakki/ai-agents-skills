#!/usr/bin/env bash
# Park a task: switch to task/<NAME> branch, stage new WIP (baseline-aware,
# no bulk-stage), commit, return to base, write .parked index.
#
# The agent writes the ## ⏸ Parked section into the card BEFORE calling this.
#
# Args: <TASK_FILE> <BASE_BRANCH> <BASELINE_FILE> <SESSION_ID> <LOG_DIR> <REASON>
# REASON: qa-fail | review-fail | blocker | question | merge-conflict
set -uo pipefail

TASK_FILE="$1"
BASE_BRANCH="$2"
BASELINE_FILE="$3"
SESSION_ID="$4"
LOG_DIR="$5"
REASON="$6"

TASK_NAME="$(basename "$TASK_FILE" .md)"
REPO="$(git rev-parse --show-toplevel 2>/dev/null || (cd "$(dirname "$TASK_FILE")/../../.." && pwd))"
TASK_BRANCH="task/${TASK_NAME}"

cd "$REPO"

# 1. Ensure on the task branch (create if first park; switch if already exists).
git switch -c "$TASK_BRANCH" 2>/dev/null || git switch "$TASK_BRANCH"

# 2. Stage new paths (beyond baseline) explicitly — never bulk-stage.
DIRTY_PATHS="$(git status --porcelain 2>/dev/null | cut -c4- | sort -u)"
BASE_PATHS="$(cut -c4- "$BASELINE_FILE" 2>/dev/null | sort -u || true)"
if [ -n "$DIRTY_PATHS" ]; then
    EXTRA="$(comm -23 \
        <(printf '%s\n' "$DIRTY_PATHS") \
        <([ -n "$BASE_PATHS" ] && printf '%s\n' "$BASE_PATHS" || true))"
    while IFS= read -r p; do
        [ -z "$p" ] && continue
        git add -- "$p"
    done <<< "$EXTRA"
fi

# 3. Commit WIP (skip if nothing staged — annotation may already have been committed).
git diff --cached --quiet || git commit -m "wip(park): ${TASK_NAME} (${REASON})"

# 4. Return to base branch (baseline dirt carries back untouched).
git switch "$BASE_BRANCH"

# 5. Write .parked index (questions live in the card annotation; index keeps the reason).
mkdir -p "${LOG_DIR}/.parked"
CARD_REL="${TASK_FILE#${REPO}/}"
cat > "${LOG_DIR}/.parked/${TASK_NAME}" <<EOF
branch=${TASK_BRANCH}
base=${BASE_BRANCH}
session=${SESSION_ID}
reason=${REASON}
card=${CARD_REL}
EOF

echo "[park] parked ${TASK_NAME} on ${TASK_BRANCH} (reason=${REASON}); base restored to ${BASE_BRANCH}"
