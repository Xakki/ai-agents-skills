#!/usr/bin/env bash
# Create a tamper-evident allowlist for one explicitly approved scheduler chain.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=task-scope.sh
source "$SCRIPT_DIR/task-scope.sh"

usage() {
    cat >&2 <<'USAGE'
Usage: create-task-scope.sh --repo DIR --approved --approval-source explicit-user|recorded-epic:ID --card TODO_CARD.md [--card TODO_CARD.md ...]

The caller must obtain explicit user approval before using --approved. The
manifest authorizes only the listed cards for execution, QA, review, merge at
ready, and chaining within that list. It never authorizes done, push, or deploy.
USAGE
}

REPO_INPUT=""
APPROVED=0
APPROVAL_SOURCE=""
CARDS=()
while [ "$#" -gt 0 ]; do
    case "$1" in
        --repo)
            [ "$#" -ge 2 ] || { usage; exit 2; }
            REPO_INPUT="$2"
            shift 2
            ;;
        --approved)
            APPROVED=1
            shift
            ;;
        --approval-source)
            [ "$#" -ge 2 ] || { usage; exit 2; }
            APPROVAL_SOURCE="$2"
            shift 2
            ;;
        --card)
            [ "$#" -ge 2 ] || { usage; exit 2; }
            CARDS+=("$2")
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            printf 'ERROR: unexpected argument: %s\n' "$1" >&2
            usage
            exit 2
            ;;
    esac
done

[ "$APPROVED" -eq 1 ] || { printf 'ERROR: --approved is required after user approval\n' >&2; exit 2; }
[ -n "$REPO_INPUT" ] || { usage; exit 2; }
[ "${#CARDS[@]}" -gt 0 ] || { printf 'ERROR: at least one --card is required\n' >&2; exit 2; }
[[ "$APPROVAL_SOURCE" = "explicit-user" || "$APPROVAL_SOURCE" =~ ^recorded-epic:[A-Za-z][A-Za-z0-9]*-[0-9]+$ ]] || {
    printf 'ERROR: unsupported approval source\n' >&2
    exit 2
}

REPO="$(git -C "$REPO_INPUT" rev-parse --show-toplevel 2>/dev/null)" || {
    printf 'ERROR: --repo is not inside a Git repository\n' >&2
    exit 1
}
REPO="$(realpath -e -- "$REPO")"
BASE_BRANCH="$(git -C "$REPO" rev-parse --abbrev-ref HEAD 2>/dev/null)" || {
    printf 'ERROR: cannot resolve current base branch\n' >&2
    exit 1
}
[ "$BASE_BRANCH" != "HEAD" ] && [[ "$BASE_BRANCH" != task/* ]] || {
    printf 'ERROR: create the scope from a checked-out base branch, not detached HEAD or task/*\n' >&2
    exit 1
}

DECLARED_REPO="$(realpath -e -- "$REPO_INPUT")"
[ "$DECLARED_REPO" = "$REPO" ] || {
    printf 'ERROR: --repo did not resolve to the Git top-level directory\n' >&2
    exit 1
}

CARD_NAMES=()
for card_path in "${CARDS[@]}"; do
    card_real="$(realpath -e -- "$card_path" 2>/dev/null)" || {
        printf 'ERROR: approved card does not exist: %s\n' "$card_path" >&2
        exit 1
    }
    task_scope_card_is_todo "$REPO" "$card_real" || {
        printf 'ERROR: approved card must be a file under this repository Kanban todo/ directory: %s\n' "$card_path" >&2
        exit 1
    }
    card_name="$(basename -- "$card_real")"
    task_scope_valid_card_name "$card_name" || {
        printf 'ERROR: card basename is not supported by the scheduler: %s\n' "$card_name" >&2
        exit 1
    }
    for existing in "${CARD_NAMES[@]}"; do
        [ "$existing" != "$card_name" ] || {
            printf 'ERROR: duplicate card in approved scope: %s\n' "$card_name" >&2
            exit 1
        }
    done
    CARD_NAMES+=("$card_name")
done

PROJECT_NAME="$(basename -- "$REPO")"
HOME_REAL="$(realpath -e -- "${HOME:-/home/coder}")" || {
    printf 'ERROR: home directory does not resolve\n' >&2
    exit 1
}
RUN_STATE_ROOT="$HOME_REAL/.local/state/claude-auto-runs"
for STATE_PATH in "$HOME_REAL/.local" "$HOME_REAL/.local/state" "$RUN_STATE_ROOT"; do
    [ ! -L "$STATE_PATH" ] || {
        printf 'ERROR: run-state ancestors must not be symlinks: %s\n' "$STATE_PATH" >&2
        exit 1
    }
done
mkdir -p -- "$RUN_STATE_ROOT"
RUN_STATE_ROOT_REAL="$(realpath -e -- "$RUN_STATE_ROOT")" || {
    printf 'ERROR: run-state root does not resolve\n' >&2
    exit 1
}
[ "$RUN_STATE_ROOT_REAL" = "$RUN_STATE_ROOT" ] || {
    printf 'ERROR: run-state root escaped the expected home state path\n' >&2
    exit 1
}
LOG_DIR="$RUN_STATE_ROOT_REAL/$PROJECT_NAME"
[ ! -L "$LOG_DIR" ] || {
    printf 'ERROR: project run-state directory must not be a symlink\n' >&2
    exit 1
}
mkdir -p -- "$LOG_DIR"
LOG_DIR_REAL="$(realpath -e -- "$LOG_DIR")" || {
    printf 'ERROR: project run-state directory does not resolve\n' >&2
    exit 1
}
[ "$LOG_DIR_REAL" = "$LOG_DIR" ] || {
    printf 'ERROR: project run-state directory escaped its expected state path\n' >&2
    exit 1
}
SCOPE_DIR="$LOG_DIR_REAL/scopes"
[ ! -L "$SCOPE_DIR" ] || {
    printf 'ERROR: scope directory must not be a symlink\n' >&2
    exit 1
}
mkdir -p -- "$SCOPE_DIR"
SCOPE_DIR_REAL="$(realpath -e -- "$SCOPE_DIR")" || {
    printf 'ERROR: scope directory does not resolve\n' >&2
    exit 1
}
[ "$SCOPE_DIR_REAL" = "$LOG_DIR_REAL/scopes" ] || {
    printf 'ERROR: scope directory escaped its expected project state path\n' >&2
    exit 1
}
SCOPE_DIR="$SCOPE_DIR_REAL"
TEMP_FILE="$(mktemp "$SCOPE_DIR/.scope.XXXXXXXX")"
trap 'rm -f -- "$TEMP_FILE"' EXIT
chmod 600 "$TEMP_FILE"
{
    printf 'format=%s\n' "$SCOPE_FORMAT"
    printf 'repo=%s\n' "$REPO"
    printf 'base=%s\n' "$BASE_BRANCH"
    printf 'approval=%s\n' "$APPROVAL_SOURCE"
    printf 'approved_at=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'permissions=execute,qa,review,merge-ready,chain-within-scope\n'
    printf 'forbid=done,push,deploy\n'
    for card_name in "${CARD_NAMES[@]}"; do
        printf 'card=%s\n' "$card_name"
    done
} > "$TEMP_FILE"

SCOPE_ID="$(sha256sum -- "$TEMP_FILE" | awk '{print $1}')"
SCOPE_FILE="$SCOPE_DIR/$SCOPE_ID.manifest"
chmod 0444 "$TEMP_FILE"
if [ -e "$SCOPE_FILE" ] || [ -L "$SCOPE_FILE" ]; then
    [ -f "$SCOPE_FILE" ] && [ ! -L "$SCOPE_FILE" ] || {
        printf 'ERROR: existing scope path is not a regular file\n' >&2
        exit 1
    }
    cmp -s -- "$TEMP_FILE" "$SCOPE_FILE" || {
        printf 'ERROR: digest collision or corrupt existing scope manifest\n' >&2
        exit 1
    }
    rm -f -- "$TEMP_FILE"
else
    mv -- "$TEMP_FILE" "$SCOPE_FILE"
fi
trap - EXIT
task_scope_load "$REPO" "$LOG_DIR" "$SCOPE_ID"
printf 'scope-id=%s\n' "$SCOPE_ID"
