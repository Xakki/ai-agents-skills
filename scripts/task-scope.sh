#!/usr/bin/env bash
# Shared validation for scoped autonomous Kanban runs.

SCOPE_FORMAT="ai-agents-schedule-scope-v1"
SCOPE_CARDS=()
SCOPE_REPO=""
SCOPE_BASE_BRANCH=""
SCOPE_APPROVAL_SOURCE=""

_task_scope_error() {
    printf 'scope error: %s\n' "$*" >&2
    return 1
}

task_scope_valid_card_name() {
    [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*\.md$ ]]
}

task_scope_todo_dir() {
    local repo="$1" candidate="$1/.agents/kanban/todo" repo_real todo_real
    if [ -d "$candidate" ]; then
        repo_real="$(realpath -e -- "$repo")" || return 1
        todo_real="$(realpath -e -- "$candidate")" || return 1
        case "$todo_real" in
            "$repo_real"/*) printf '%s\n' "$todo_real"; return 0 ;;
            *) _task_scope_error 'Kanban todo directory resolves outside the repository'; return 1 ;;
        esac
    fi
    _task_scope_error "no canonical .agents Kanban todo directory in $repo"
}

task_scope_card_is_todo() {
    local repo="$1" card="$2" todo_dir card_real
    todo_dir="$(task_scope_todo_dir "$repo")" || return 1
    card_real="$(realpath -e -- "$card" 2>/dev/null)" || return 1
    [ -f "$card_real" ] && [ "$(dirname -- "$card_real")" = "$todo_dir" ]
}

task_scope_contains() {
    local wanted="$1" card
    for card in "${SCOPE_CARDS[@]}"; do
        [ "$card" = "$wanted" ] && return 0
    done
    return 1
}

task_scope_shell_quote() {
    local value="$1"
    value="${value//\'/\'\\\'\'}"
    printf "'%s'" "$value"
}

task_scope_job_command() {
    printf 'exec %s %s %s' \
        "$(task_scope_shell_quote "$1")" \
        "$(task_scope_shell_quote "$2")" \
        "$(task_scope_shell_quote "$3")"
}

task_scope_job_matches() {
    local job_script="$1" expected_command="$2"
    [ -n "$expected_command" ] || return 1
    grep -Fqx -- "$expected_command" <<< "$job_script"
}

task_scope_job_scope_matches() {
    local job_script="$1" runner="$2" scope_id="$3" todo_dir="$4"
    shift 4
    local card expected_command
    for card in "$@"; do
        task_scope_valid_card_name "$card" || continue
        expected_command="$(task_scope_job_command "$runner" "$todo_dir/$card" "$scope_id")"
        task_scope_job_matches "$job_script" "$expected_command" && return 0
    done
    return 1
}

task_scope_acquire_lock() {
    local repo_input="$1" log_dir="$2" scope_id="$3"
    local repo_real home_real log_dir_real expected_log_dir scope_dir scope_dir_real
    local lock_file lock_file_real fd_path_real file_identity fd_identity old_umask

    [[ "$scope_id" =~ ^[0-9a-f]{64}$ ]] || {
        _task_scope_error "invalid scope id for lock"
        return 1
    }
    command -v flock >/dev/null 2>&1 || {
        _task_scope_error "flock is required for scoped scheduler runs"
        return 1
    }
    repo_real="$(git -C "$repo_input" rev-parse --show-toplevel 2>/dev/null)" || {
        _task_scope_error "cannot resolve repository for scope lock"
        return 1
    }
    repo_real="$(realpath -e -- "$repo_real")" || {
        _task_scope_error "repository root does not resolve for scope lock"
        return 1
    }
    home_real="$(realpath -e -- "${HOME:?HOME must be set}")" || {
        _task_scope_error "home directory does not resolve for scope lock"
        return 1
    }
    [ ! -L "$log_dir" ] || {
        _task_scope_error "run-state directory must not be a symlink"
        return 1
    }
    log_dir_real="$(realpath -e -- "$log_dir")" || {
        _task_scope_error "run-state directory does not resolve for scope lock"
        return 1
    }
    expected_log_dir="$home_real/.local/state/claude-auto-runs/$(basename -- "$repo_real")"
    [ "$log_dir_real" = "$expected_log_dir" ] || {
        _task_scope_error "run-state directory is outside the expected project state path"
        return 1
    }
    scope_dir="$log_dir_real/scopes"
    [ ! -L "$scope_dir" ] || {
        _task_scope_error "scope directory must not be a symlink"
        return 1
    }
    scope_dir_real="$(realpath -e -- "$scope_dir")" || {
        _task_scope_error "scope directory does not resolve for lock"
        return 1
    }
    [ "$scope_dir_real" = "$log_dir_real/scopes" ] || {
        _task_scope_error "scope directory is outside the expected project state path"
        return 1
    }

    lock_file="$scope_dir_real/$scope_id.lock"
    [ ! -L "$lock_file" ] || {
        _task_scope_error "scope lock file must not be a symlink"
        return 1
    }
    if [ -e "$lock_file" ] && [ ! -f "$lock_file" ]; then
        _task_scope_error "scope lock path is not a regular file"
        return 1
    fi

    old_umask="$(umask)"
    umask 077
    if ! exec {SCOPE_LOCK_FD}>>"$lock_file"; then
        umask "$old_umask"
        _task_scope_error "cannot open scope lock file"
        return 1
    fi
    umask "$old_umask"

    lock_file_real="$(realpath -e -- "$lock_file" 2>/dev/null)" || lock_file_real=""
    fd_path_real="$(realpath -e -- "/proc/$$/fd/$SCOPE_LOCK_FD" 2>/dev/null)" || fd_path_real=""
    file_identity="$(stat -Lc '%d:%i' -- "$lock_file" 2>/dev/null)" || file_identity=""
    fd_identity="$(stat -Lc '%d:%i' -- "/proc/$$/fd/$SCOPE_LOCK_FD" 2>/dev/null)" || fd_identity=""
    if [ -L "$lock_file" ] || [ "$lock_file_real" != "$lock_file" ] \
        || [ "$fd_path_real" != "$lock_file" ] || [ -z "$file_identity" ] \
        || [ "$file_identity" != "$fd_identity" ]; then
        exec {SCOPE_LOCK_FD}>&-
        unset SCOPE_LOCK_FD
        _task_scope_error "scope lock path changed or escaped its expected directory"
        return 1
    fi
    if ! flock -n "$SCOPE_LOCK_FD"; then
        exec {SCOPE_LOCK_FD}>&-
        unset SCOPE_LOCK_FD
        _task_scope_error "another run already holds this approved scope"
        return 1
    fi

    lock_file_real="$(realpath -e -- "$lock_file" 2>/dev/null)" || lock_file_real=""
    fd_path_real="$(realpath -e -- "/proc/$$/fd/$SCOPE_LOCK_FD" 2>/dev/null)" || fd_path_real=""
    file_identity="$(stat -Lc '%d:%i' -- "$lock_file" 2>/dev/null)" || file_identity=""
    fd_identity="$(stat -Lc '%d:%i' -- "/proc/$$/fd/$SCOPE_LOCK_FD" 2>/dev/null)" || fd_identity=""
    if [ -L "$lock_file" ] || [ "$lock_file_real" != "$lock_file" ] \
        || [ "$fd_path_real" != "$lock_file" ] || [ -z "$file_identity" ] \
        || [ "$file_identity" != "$fd_identity" ]; then
        task_scope_release_lock
        _task_scope_error "scope lock path changed after acquisition"
        return 1
    fi
    return 0
}

task_scope_release_lock() {
    [ -n "${SCOPE_LOCK_FD:-}" ] || return 0
    flock -u "$SCOPE_LOCK_FD" 2>/dev/null || true
    exec {SCOPE_LOCK_FD}>&-
    unset SCOPE_LOCK_FD
}

task_scope_load() {
    local repo_input="$1" log_dir="$2" scope_id="$3"
    local repo_real home_real expected_log_dir log_dir_real scope_dir scope_dir_real scope_file scope_file_real digest
    local line value current_branch
    local seen_format=0 seen_repo=0 seen_base=0 seen_approval=0 seen_approved_at=0
    local seen_permissions=0 seen_forbid=0
    local -a parsed_cards=()

    if [[ ! "$scope_id" =~ ^[a-f0-9]{64}$ ]]; then
        _task_scope_error "scope id must be a 64-character lowercase SHA-256 digest"
        return 1
    fi
    repo_real="$(git -C "$repo_input" rev-parse --show-toplevel 2>/dev/null)" || {
        _task_scope_error "cannot resolve repository root"
        return 1
    }
    repo_real="$(realpath -e -- "$repo_real")" || {
        _task_scope_error "repository root does not resolve"
        return 1
    }

    home_real="$(realpath -e -- "${HOME:?HOME must be set}")" || {
        _task_scope_error "home directory does not resolve"
        return 1
    }
    [ ! -L "$log_dir" ] || {
        _task_scope_error "run-state directory must not be a symlink"
        return 1
    }
    log_dir_real="$(realpath -e -- "$log_dir")" || {
        _task_scope_error "run-state directory does not resolve"
        return 1
    }
    expected_log_dir="$home_real/.local/state/claude-auto-runs/$(basename -- "$repo_real")"
    [ "$log_dir_real" = "$expected_log_dir" ] || {
        _task_scope_error "run-state directory is outside the expected project state path"
        return 1
    }

    scope_dir="$log_dir_real/scopes"
    [ ! -L "$scope_dir" ] || {
        _task_scope_error "scope directory must not be a symlink"
        return 1
    }
    [ -d "$scope_dir" ] || {
        _task_scope_error "scope directory is missing"
        return 1
    }
    scope_dir_real="$(realpath -e -- "$scope_dir")" || {
        _task_scope_error "scope directory does not resolve"
        return 1
    }
    [ "$scope_dir_real" = "$log_dir_real/scopes" ] || {
        _task_scope_error "scope directory is outside the expected project state path"
        return 1
    }
    scope_dir="$scope_dir_real"
    scope_file="$scope_dir/$scope_id.manifest"
    [ -f "$scope_file" ] && [ ! -L "$scope_file" ] || {
        _task_scope_error "scope manifest is missing or is not a regular file"
        return 1
    }
    scope_file_real="$(realpath -e -- "$scope_file")" || {
        _task_scope_error "scope manifest does not resolve"
        return 1
    }
    [ "$scope_file_real" = "$scope_dir_real/$scope_id.manifest" ] || {
        _task_scope_error "scope manifest escaped its state directory"
        return 1
    }
    digest="$(sha256sum -- "$scope_file" | awk '{print $1}')" || {
        _task_scope_error "cannot hash scope manifest"
        return 1
    }
    [ "$digest" = "$scope_id" ] || {
        _task_scope_error "manifest hash/digest does not match scope id"
        return 1
    }

    while IFS= read -r line || [ -n "$line" ]; do
        [ -n "$line" ] || {
            _task_scope_error "manifest contains an empty line"
            return 1
        }
        case "$line" in
            "format=$SCOPE_FORMAT")
                [ "$seen_format" -eq 0 ] || { _task_scope_error "duplicate format field"; return 1; }
                seen_format=1
                ;;
            repo=*)
                [ "$seen_repo" -eq 0 ] || { _task_scope_error "duplicate repository field"; return 1; }
                SCOPE_REPO="${line#repo=}"
                seen_repo=1
                ;;
            base=*)
                [ "$seen_base" -eq 0 ] || { _task_scope_error "duplicate base branch field"; return 1; }
                SCOPE_BASE_BRANCH="${line#base=}"
                seen_base=1
                ;;
            approval=*)
                [ "$seen_approval" -eq 0 ] || { _task_scope_error "duplicate approval field"; return 1; }
                SCOPE_APPROVAL_SOURCE="${line#approval=}"
                seen_approval=1
                ;;
            approved_at=*)
                [ "$seen_approved_at" -eq 0 ] || { _task_scope_error "duplicate approval timestamp"; return 1; }
                value="${line#approved_at=}"
                [[ "$value" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || {
                    _task_scope_error "invalid approval timestamp"
                    return 1
                }
                seen_approved_at=1
                ;;
            permissions=execute,qa,review,merge-ready,chain-within-scope)
                [ "$seen_permissions" -eq 0 ] || { _task_scope_error "duplicate permissions field"; return 1; }
                seen_permissions=1
                ;;
            forbid=done,push,deploy)
                [ "$seen_forbid" -eq 0 ] || { _task_scope_error "duplicate forbid field"; return 1; }
                seen_forbid=1
                ;;
            card=*)
                value="${line#card=}"
                task_scope_valid_card_name "$value" || {
                    _task_scope_error "invalid card basename in manifest"
                    return 1
                }
                local existing
                for existing in "${parsed_cards[@]}"; do
                    [ "$existing" != "$value" ] || {
                        _task_scope_error "duplicate card in manifest: $value"
                        return 1
                    }
                done
                parsed_cards+=("$value")
                ;;
            *)
                _task_scope_error "unknown or invalid manifest field"
                return 1
                ;;
        esac
    done < "$scope_file"

    [ "$seen_format" -eq 1 ] && [ "$seen_repo" -eq 1 ] && [ "$seen_base" -eq 1 ] \
        && [ "$seen_approval" -eq 1 ] && [ "$seen_approved_at" -eq 1 ] \
        && [ "$seen_permissions" -eq 1 ] && [ "$seen_forbid" -eq 1 ] \
        && [ "${#parsed_cards[@]}" -gt 0 ] || {
            _task_scope_error "manifest is incomplete"
            return 1
        }
    [ "$SCOPE_REPO" = "$repo_real" ] || {
        _task_scope_error "scope repository does not match current repository"
        return 1
    }
    [[ "$SCOPE_APPROVAL_SOURCE" = "explicit-user" || "$SCOPE_APPROVAL_SOURCE" =~ ^recorded-epic:[A-Za-z][A-Za-z0-9]*-[0-9]+$ ]] || {
        _task_scope_error "approval source is not recognized"
        return 1
    }
    current_branch="$(git -C "$repo_real" rev-parse --abbrev-ref HEAD 2>/dev/null)" || {
        _task_scope_error "cannot resolve current base branch"
        return 1
    }
    [ "$current_branch" != "HEAD" ] && [[ "$current_branch" != task/* ]] || {
        _task_scope_error "detached HEAD or task/* branch is not a valid scheduler base"
        return 1
    }
    [ "$current_branch" = "$SCOPE_BASE_BRANCH" ] || {
        _task_scope_error "current branch does not match the approved base branch"
        return 1
    }

    SCOPE_CARDS=("${parsed_cards[@]}")
    return 0
}
