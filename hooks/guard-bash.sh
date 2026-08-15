#!/usr/bin/env bash
# PreToolUse(Bash) guard, global.
#
# SCOPE — make is required only for talking to SERVICES, CONTAINERS and language
# RUNTIMES: docker/compose, package managers, python/php/node/go toolchains, DB
# clients, web servers. Plain shell is NOT in scope and is never redirected to a
# make target: ls, find, grep, sed, awk, cat, jq, curl, tar, cp, mkdir, chmod,
# diff, xargs, read-only git — all pass through untouched.
#
# The only non-service rules here are safety, not routing: recursive delete and
# git working-tree destruction (rollback policy), which block regardless of make.
#
# Exit 2 = block, stderr = reason shown to the agent. Exit 0 = allow.
#
# Deliberately conservative: it matches command TEXT, so obfuscation defeats it.
# A guardrail against slips, not a security boundary.
#
# Escape hatch — a project that legitimately runs a host binary adds ERE patterns,
# one per line, to <project>/.claude/guard-allow.txt (# comments allowed). Any
# match short-circuits to allow. Keep the patterns narrow and say why in a comment.
#
# Tested by skills/agent-config-test/test-hooks.sh (cases/guard-bash.tsv).
set -uo pipefail

input=$(cat)
cmd=$(jq -r '.tool_input.command // empty' <<<"$input" 2>/dev/null) || exit 0
[[ -z "$cmd" ]] && exit 0

proj=$(jq -r '.cwd // empty' <<<"$input" 2>/dev/null)
proj=${CLAUDE_PROJECT_DIR:-${proj:-$PWD}}

allow_file="$proj/.claude/guard-allow.txt"
if [[ -f "$allow_file" ]]; then
	while IFS= read -r pat; do
		[[ -z "$pat" || "$pat" == \#* ]] && continue
		[[ "$cmd" =~ $pat ]] && exit 0
	done <"$allow_file"
fi

block() {
	# The allowlist is optional, so the hint has to say "create" when it is absent
	# — pointing at a path that does not exist reads as a broken config.
	local hint="Legitimate host call? Add a narrow ERE to $allow_file"
	[[ -f "$allow_file" ]] || hint="Legitimate host call? The optional allowlist $allow_file
does not exist yet — create it and put a narrow ERE in it."
	printf 'BLOCKED by the global guard-bash hook: %s\n\n%s\n\n%s\n' "$1" "$2" "$hint" >&2
	exit 2
}

via_make="This talks to a service/container/runtime, so it goes through
'make <target>'. No suitable target => ADD one to the Makefile (one-line '##'
description), then use it. Plain shell utilities need no target — only
services, containers and language runtimes do."

# Command position: start of string, a newline, or a shell separator — then any
# env/time/nohup prefix and VAR=val assignments.
#   - bare whitespace as the anchor false-positives on arguments (`grep -r pytest .`)
#   - bare `^` misses line 2+, since bash anchors ^ to string start, not line start
#   - without the VAR= hop, `FOO=1 docker compose up` slips through
CMD='(^|[;&|()]|'$'\n'')[[:space:]]*((env|time|nohup|exec|sudo)[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*'
# Local binary dirs: ./vendor/bin/phpunit, node_modules/.bin/jest, .venv/bin/pytest
BIN='((\./)?[A-Za-z0-9_./-]*(vendor/bin|node_modules/\.bin|\.venv/bin|venv/bin)/)?'

# --- 1. Destructive filesystem ----------------------------------------------
if [[ "$cmd" =~ (^|[[:space:];&|])rm[[:space:]]+(-[a-zA-Z]*[rR][a-zA-Z]*f|-[a-zA-Z]*f[a-zA-Z]*[rR]|-r[[:space:]]+-f|-f[[:space:]]+-r) ]] \
	&& [[ ! "$cmd" =~ /tmp/backup/ ]]; then
	block "recursive force-delete" \
"Never delete files — rename with a 'backup_' prefix into /tmp/backup/<project>/.
A real deletion needs an explicit 'yes' from the user first."
fi

# --- 2. Git history / working-tree destruction ------------------------------
if [[ "$cmd" =~ git[[:space:]].*push.*(--force([^-]|$)|[[:space:]]-f([[:space:]]|$)) ]]; then
	block "git push --force" \
"Force-push rewrites published history. Use --force-with-lease and get explicit
user approval first (skill git-flow)."
fi

# reset --hard, clean -fd, restore, stash drop/clear, and the two discard forms
# of checkout. Branch switching ('checkout main', 'checkout -b feat') stays allowed.
if [[ "$cmd" =~ git[[:space:]]+(reset[[:space:]]+--hard|clean[[:space:]]+-[a-zA-Z]*[dfx]|restore([[:space:]]|$)|stash[[:space:]]+(drop|clear)) ]] \
	|| [[ "$cmd" =~ git[[:space:]]+checkout[[:space:]]+\.([[:space:]]|$) ]] \
	|| [[ "$cmd" =~ git[[:space:]]+checkout([[:space:]]+[^[:space:]-][^[:space:]]*)*[[:space:]]+--([[:space:]]|$) ]]; then
	block "git working-tree rollback" \
"Rollbacks require an explicit 'yes' from the user. Default is to COMMIT what
exists, even if the diff looks trivial. Ask before discarding."
fi

if [[ "$cmd" =~ git[[:space:]]+worktree[[:space:]]+remove.*--force ]]; then
	block "git worktree remove --force" \
"This is an rm -rf of the worktree and destroys untracked files. Run
'git status --porcelain' on it first and move anything untracked to /tmp/backup/."
fi

# --- 3. Docker driven directly ----------------------------------------------
# Blocked: lifecycle verbs. Allowed: config, ps, port, logs, top, images, inspect,
# version, stats — read-only inspection needs no target.
if [[ "$cmd" =~ ${CMD}docker[-[:space:]]+compose[[:space:]]+(up|down|build|create|start|stop|restart|kill|rm|run|exec|cp|pull|push|scale|watch|wait) ]] \
	|| [[ "$cmd" =~ ${CMD}docker[[:space:]]+(run|exec|build|create|start|stop|restart|kill|rm|rmi|cp|commit|push|update|prune)([[:space:]]|$) ]] \
	|| [[ "$cmd" =~ ${CMD}docker[[:space:]]+(volume|network|system|image|container|builder)[[:space:]]+(rm|prune|create) ]]; then
	block "direct docker / docker compose command" \
"The stack is never driven by docker directly. $via_make
Read-only 'docker ps|logs|inspect|stats' and 'docker compose config|ps|port|logs'
stay allowed."
fi

# --- 4. Host toolchain instead of the container -----------------------------
# Global rule: Docker only, never a bare host toolchain. Each stack's entry point
# is a make target that runs the tool inside the project's image.
if [[ "$cmd" =~ ${CMD}(pip|pip3|uv|poetry|pdm)[[:space:]]+(pip[[:space:]]+)?(install|add|remove|sync|lock|run|venv) ]] \
	|| [[ "$cmd" =~ ${CMD}(npm|yarn|pnpm|bun)[[:space:]]+(install|i|ci|add|remove|update|run|build|start|test|exec) ]] \
	|| [[ "$cmd" =~ ${CMD}npx[[:space:]] ]] \
	|| [[ "$cmd" =~ ${CMD}composer[[:space:]]+(install|update|require|remove|dump-autoload) ]]; then
	block "direct dependency install / package-manager run" \
"Dependencies belong in the container image, not on the host. $via_make"
fi

if [[ "$cmd" =~ ${CMD}${BIN}(pytest|tox|nox|ruff|mypy|black|isort|flake8|pylint|alembic|uvicorn|gunicorn|celery)([[:space:]]|$) ]] \
	|| [[ "$cmd" =~ ${CMD}python3?[[:space:]]+-m[[:space:]]+(pytest|ruff|mypy|black|flake8|alembic|uvicorn|celery|http\.server) ]] \
	|| [[ "$cmd" =~ ${CMD}${BIN}(phpunit|pest|phpstan|psalm|php-cs-fixer|rector)([[:space:]]|$) ]] \
	|| [[ "$cmd" =~ ${CMD}php[[:space:]]+(artisan|-S)([[:space:]]|$) ]] \
	|| [[ "$cmd" =~ ${CMD}${BIN}(jest|vitest|eslint|prettier|tsc|vite|webpack|nest)([[:space:]]|$) ]] \
	|| [[ "$cmd" =~ ${CMD}go[[:space:]]+(build|run|test|install|generate|mod)([[:space:]]|$) ]] \
	|| [[ "$cmd" =~ ${CMD}(mysql|mariadb|psql|mongosh|redis-cli|keydb-cli)([[:space:]]|$) ]]; then
	block "bare host toolchain call" \
"This runs on the host, against the wrong environment — wrong interpreter
version, missing extensions, no service network. $via_make"
fi

# --- 5. Web servers and process supervisors ---------------------------------
# `nginx -v/-V` is a version print and stays allowed; everything else drives a
# running service. Read-only `systemctl status|list-units` stays allowed too.
if { [[ "$cmd" =~ ${CMD}(nginx|apache2ctl|apachectl|httpd|php-fpm|supervisorctl|certbot)([[:space:]]|$) ]] \
	&& [[ ! "$cmd" =~ ${CMD}nginx[[:space:]]+-[vV]([[:space:]]|$) ]]; } \
	|| [[ "$cmd" =~ ${CMD}systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask) ]]; then
	block "web server / service control from the host" \
"Services here are containers, not host daemons — a host nginx/php-fpm/systemctl
call hits the wrong thing or nothing at all. $via_make
Host-level service control that genuinely needs root goes to the user as a
ready-to-paste command instead."
fi

exit 0
