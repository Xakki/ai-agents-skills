#!/usr/bin/env bash
# Runs INSIDE the spawned tmux window. Launches interactive claude with an
# autonomous prompt. Window stays open after claude exits.
#
# Repository and board are resolved from the task and scope interface.
set -uo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TASK_FILE="${1:?usage: $0 <absolute-path-to-task.md> <scope-id>}"
SCOPE_ID="${2:?usage: $0 <absolute-path-to-task.md> <scope-id>}"
TASK_FILE="$(realpath -e -- "$TASK_FILE")" || {
    printf 'ERROR: task file does not exist\n' >&2
    exit 1
}
TASK_BASENAME="$(basename -- "$TASK_FILE")"
TASK_NAME="$(basename -- "$TASK_FILE" .md)"
PROJECT_DIR="$(git -C "$(dirname -- "$TASK_FILE")" rev-parse --show-toplevel 2>/dev/null)" || {
    printf 'ERROR: task file is not inside a Git repository\n' >&2
    exit 1
}
PROJECT_DIR="$(realpath -e -- "$PROJECT_DIR")"
PROJECT_NAME="$(basename "$PROJECT_DIR")"
# Claude Code stores session JSONL under ~/.claude/projects/<encoded-path>/,
# where <encoded-path> = absolute project dir with every '/' replaced by '-'.
CLAUDE_PROJECT_PATH="$(printf '%s' "$PROJECT_DIR" | tr '/' '-')"
REPO="$PROJECT_DIR"
BASE_BRANCH="$(git -C "$REPO" rev-parse --abbrev-ref HEAD)"
case "$BASE_BRANCH" in
    task/*)
        echo "ERROR: auto-run started on a task/* branch ($BASE_BRANCH) — refusing; check out the base branch first" >&2
        exit 1
        ;;
esac
# shellcheck source=task-scope.sh
source "$SCRIPT_DIR/task-scope.sh"
: "${HOME:?HOME must be set}"
LOG_DIR="$HOME/.local/state/claude-auto-runs/${PROJECT_NAME}"
task_scope_load "$REPO" "$LOG_DIR" "$SCOPE_ID" || exit 1
task_scope_contains "$TASK_BASENAME" || {
    printf 'ERROR: task is outside the approved scope: %s\n' "$TASK_BASENAME" >&2
    exit 1
}
task_scope_card_is_todo "$REPO" "$TASK_FILE" || {
    printf 'ERROR: scheduled task is no longer in todo/: %s\n' "$TASK_BASENAME" >&2
    exit 1
}
TODO_DIR="$(task_scope_todo_dir "$REPO")" || exit 1
BOARD_DIR="$(dirname -- "$TODO_DIR")"
SCOPE_TEXT="$(printf '  - %s\n' "${SCOPE_CARDS[@]}")"
TS="$(date +%Y%m%d_%H%M%S)"
# Logs MUST live OUTSIDE the repo. The autonomous prompt previously ran
# `git stash push -u`, which stashed the open --debug-file mid-write and
# crashed claude with ENOENT (appendFileSync to a vanished file).
# Predetermined session ID so user can `claude --resume <id>` to inspect history.
SESSION_ID="$(cat /proc/sys/kernel/random/uuid)"
DEBUG_LOG="$LOG_DIR/${TS}_${TASK_NAME}_${SESSION_ID}.debug.log"
META_LOG="$LOG_DIR/${TS}_${TASK_NAME}_${SESSION_ID}.meta.log"

mkdir -p "$LOG_DIR"
# Serialize the runner across different approved scopes in this repository.
# The manifest remains scope-specific; only the lock key is repo-wide.
REPOSITORY_LOCK_ID="$(printf 'repo:%s' "$REPO" | sha256sum | cut -d ' ' -f 1)"
task_scope_acquire_lock "$REPO" "$LOG_DIR" "$REPOSITORY_LOCK_ID" || exit 1
cd "$REPO"
STATUS="$(git status --porcelain --untracked-files=normal)" || { echo "ERROR: cannot inspect repository state" >&2; exit 1; }
if [ -n "$STATUS" ]; then
    echo "ERROR: staged, unstaged or untracked work exists; preserve it and stop the scheduled run" >&2
    exit 1
fi
BASELINE_FILE="$(mktemp "$LOG_DIR/.baseline-dirty.XXXXXXXXXX")" || {
    echo "ERROR: could not create an exclusive baseline file" >&2; exit 1;
}

BASE_BRANCH="$SCOPE_BASE_BRANCH"
export SCHEDULE_SCOPE_ID="$SCOPE_ID"

PROMPT=$(cat <<PROMPT_EOF
Complete the authorized card at \`${TASK_FILE}\`. The resolved board root is \`${BOARD_DIR}\`.
Approved scope identifier: \`${SCOPE_ID}\`. The listed card basenames are:
${SCOPE_TEXT}
The manifest is an integrity-checked record of supplied scope, not independent proof of user consent. Honor the actual user's instructions and all project rules. Do not add cards from the backlog. Read the actual board helper and project instructions through the available interface; do not assume a particular agent file, host, branch or board layout.

Work only within the authorized action and path scope. Preserve unrelated staged, unstaged and untracked data. Before any commit inspect the entire index, not only the paths you just added; do not commit unrelated staged content. Do not stash, reset, clean, force a branch switch, bypass hooks, or use bulk staging. Review the card's prerequisites and required test and review gates before any stage transition. A timeout or a native security/approval refusal is not consent. The required explicit user approval for \`done\` remains separate from merge, push, deploy, scheduling or notification authority. When scope, consent, a safe checkpoint or an independent reviewer is missing, stop and report the actual blocker, preserving all work. Do not infer that a hash or a successful test grants any extra action.

To checkpoint work that cannot continue (QA failure, review failure, blocker, question or merge conflict) you may run once \`${SCRIPT_DIR}/park-task.sh '${TASK_FILE}' '${BASE_BRANCH}' '${BASELINE_FILE}' '${SESSION_ID}' '${LOG_DIR}' <reason>\`, where reason is qa-fail, review-fail, blocker, question or merge-conflict. It snapshots the working-tree changes to a new side branch task/<card> and records .parked/<card> without switching branches, staging, stashing or cleaning; the working tree stays as it is. Never run park-task-clean.sh or otherwise restore, reset or clean the tree: that is a separate owner-run step. Afterwards stop, report the blocker and end with AUTO-RUN-RESULT: park. A refusal means nothing was parked: report it and stop.

If this specific run and exact card allowlist authorize a subsequent scheduled continuation, the existing helper can be invoked only within those instructions; do not enqueue further tasks directly. Do not send notifications unless specifically authorized. Report the actual checks and action results, including unrun gates and whether changes remain staged. End with AUTO-RUN-RESULT: <ok|park|skip>: ${TASK_NAME}: <reason> only after the work and any authorized continuation are complete.
PROMPT_EOF
)

{
    echo "================================================================"
    echo "=== AUTO RUN START $(date)"
    echo "=== TASK   : $TASK_NAME"
    echo "=== FILE   : $TASK_FILE"
    echo "=== HEAD   : $(git rev-parse --short HEAD 2>/dev/null) on $(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
    echo "=== SESSION: $SESSION_ID"
    echo "=== RESUME : claude --resume $SESSION_ID"
    echo "=== VIEW   : $SCRIPT_DIR/view-task-history.sh $SESSION_ID"
    echo "=== DEBUG  : $DEBUG_LOG"
    echo "================================================================"
} | tee -a "$META_LOG"

START_EPOCH=$(date +%s)
claude \
    --session-id "$SESSION_ID" \
    --debug-file "$DEBUG_LOG" \
    "$PROMPT"
EXIT=$?
WALL_SEC=$(( $(date +%s) - START_EPOCH ))

# Detect run result by grepping the JSONL for the final AUTO-RUN-RESULT marker.
# Agent often wraps the marker in backticks (`AUTO-RUN-RESULT: ok: ...`); accept
# any preceding char, anchor on canonical "AUTO-RUN-RESULT: <verdict>:" shape.
RESULT="unknown"
JSONL="$HOME/.claude/projects/${CLAUDE_PROJECT_PATH}/${SESSION_ID}.jsonl"
if [ -f "$JSONL" ]; then
    LAST_RESULT=$(grep -hoE 'AUTO-RUN-RESULT: (ok|skip|park):' "$JSONL" | tail -1 | sed -E 's/.*: ([a-z]+):/\1/')
    [ -n "$LAST_RESULT" ] && RESULT="$LAST_RESULT"
fi
if [ "$EXIT" -ne 0 ]; then
    RESULT="unknown"
fi

{
    echo
    echo "================================================================"
    echo "=== AUTO RUN END $(date), claude exit=$EXIT, result=$RESULT, wall=${WALL_SEC}s"
    echo "================================================================"
} | tee -a "$META_LOG"

# Token/cost summary → stdout + appended to task file.
echo
echo "================================================================"
echo "=== USAGE SUMMARY"
echo "================================================================"
TASK_USAGE_READ_ONLY=1 "$SCRIPT_DIR/summarize-task-usage.sh" "$SESSION_ID" "$TASK_FILE" "$WALL_SEC" "$EXIT" "$RESULT" 2>&1 | tee -a "$META_LOG"

# A scheduler cannot prove ownership of all staged entries or task-output paths.
# Do not automatically stage or commit any content. Leave the exact state for
# the authorized project workflow to inspect and report.
echo "[inner] automatic staging and commit disabled; inspect repository state"

# Cancel only this scope's queued task, used if a prompt ever emits an invalid marker.
cancel_scope_jobs() {
    # This process does not have immutable receipts for jobs created by itself.
    # Matching scope or commands is not proof that an existing job is ours.
    echo "[chain] WARN: continuation state requires manual review; no queued jobs were cancelled"
}

SCOPE_VALID=true
task_scope_load "$REPO" "$LOG_DIR" "$SCOPE_ID" || SCOPE_VALID=false

# === Chain verification (the scope-aware helper enqueues at step 9) ===
# Runs after claude exits, before the user closes the retained inspection window.
{
    echo
    echo "================================================================"
    echo "=== CHAIN (verify)"
    echo "================================================================"
    NEXT_MARK=""
    if [ -f "$JSONL" ]; then
        # Tight: basename = [A-Za-z0-9._-]+ OR exact literal "none".
        # Without this the agent's prose ('AUTO-RUN-NEXT: none`') leaks the
        # trailing backtick into NEXT_MARK and we go down the ok:* enqueue
        # branch trying to verify a job for "none`".
        NEXT_MARK=$(grep -hoE 'AUTO-RUN-NEXT: ([A-Za-z0-9._-]+|none)' "$JSONL" | tail -1 | sed -E 's/^AUTO-RUN-NEXT: //')
    fi
    case "$RESULT:$NEXT_MARK" in
        ok:none|park:none|skip:none)
            cancel_scope_jobs ""
            echo "[chain] untrusted session text reports result=$RESULT and no continuation; verify actual state independently"
            ;;
        ok:|park:|skip:)
            cancel_scope_jobs ""
            echo "[chain] ERROR: result=$RESULT but no AUTO-RUN-NEXT marker — chain was not advanced"
            ;;
        ok:*|park:*|skip:*)
            if [ "$SCOPE_VALID" != true ]; then
                cancel_scope_jobs "$NEXT_MARK"
                echo "[chain] ERROR: scope validation failed after run; queued continuation cancelled"
            elif ! task_scope_contains "$NEXT_MARK"; then
                cancel_scope_jobs "$NEXT_MARK"
                echo "[chain] ERROR: next card is outside the approved scope; queued continuation cancelled"
            else
                FOUND=""
                TODO_DIR="$(task_scope_todo_dir "$REPO" 2>/dev/null)"
                EXPECTED_COMMAND="$(task_scope_job_command "$SCRIPT_DIR/run-claude-task.sh" "$TODO_DIR/$NEXT_MARK" "$SCOPE_ID")"
                for j in $(atq 2>/dev/null | awk '{print $1}'); do
                    JOB_COMMAND="$(at -c "$j" 2>/dev/null)"
                    if task_scope_job_matches "$JOB_COMMAND" "$EXPECTED_COMMAND"; then
                        FOUND="$j"
                        break
                    fi
                done
                if [ -n "$FOUND" ]; then
                    echo "[chain] matching at-job #$FOUND exists for $NEXT_MARK; origin and authorization require independent verification"
                    atq | sort -k 2
                else
                    echo "[chain] WARN: scoped helper reported $NEXT_MARK but no matching at-job is queued"
                fi
            fi
            ;;
        *)
            cancel_scope_jobs ""
            echo "[chain] result=$RESULT — chain stops and scoped queue is cleared"
            ;;
    esac
} | tee -a "$META_LOG"

rm -f "$BASELINE_FILE"

# The task and chain decision are finished. Do not hold the scheduler lock
# while the user leaves this interactive window open for inspection.
task_scope_release_lock

echo
echo ">>> Window kept open. Press Enter to close."
read -r _ || true
# A failed Claude process or a missing result is not a successful scheduler run.
if [ "$EXIT" -ne 0 ] || [ "$RESULT" = unknown ]; then
    exit 1
fi
