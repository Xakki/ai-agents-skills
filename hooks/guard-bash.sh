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

# --- Quote-aware routing scan (sections 3/4/5 ONLY — never sections 1/2) ----
# `make -C docker run CMD="pytest tests/ && ruff check"` must be ALLOWED: the
# `&&` and `pytest`/`ruff` text live inside a quoted VALUE handed to make, not
# a command position in the agent's own shell. Routing rules (docker/toolchain/
# webserver, sections 3-5) must not treat a separator or tool name inside
# quotes as real. Safety rules (sections 1-2) are the opposite on purpose —
# they scan $cmd raw, below — because a destructive command hidden inside a
# quoted make argument (`make run CMD="rm -rf /x"`) is still a real rm once
# whatever consumes CMD runs it, and must block regardless of make.
#
# neutralize_quotes replaces the CONTENTS of every '...'/"..." span with '#',
# keeping the quote characters and the string length, so CMD's positional
# anchors still line up outside quotes while nothing inside a quote can ever
# look like a separator or a tool name to sections 3-5. Backslash-escaped
# characters inside double quotes are neutralised too without toggling the
# quote state on them.
neutralize_quotes() {
	local s=$1 out='' c i=0 len=${#1} insq=0 indq=0
	while (( i < len )); do
		c=${s:i:1}
		if (( insq )); then
			[[ "$c" == "'" ]] && { insq=0; out+="$c"; } || out+='#'
		elif (( indq )); then
			if [[ "$c" == '\' && $((i + 1)) -lt $len ]]; then
				out+='##'; (( i++ ))
			elif [[ "$c" == '"' ]]; then
				indq=0; out+="$c"
			else
				out+='#'
			fi
		elif [[ "$c" == "'" ]]; then
			insq=1; out+="$c"
		elif [[ "$c" == '"' ]]; then
			indq=1; out+="$c"
		else
			out+="$c"
		fi
		(( i++ ))
	done
	printf '%s' "$out"
}
scan_cmd=$(neutralize_quotes "$cmd")

# --- 1-2. Destructive filesystem / git — executor-aware safety scan ---------
# check_destructive scans ONE command string with ONE anchor pair; called
# twice below, never merged into one over-permissive pass:
#
#   1) default pass — $scan_cmd (quotes neutralised) with the ORIGINAL,
#      narrow anchors. This is what blocks a bare `rm -rf /var/lib/x` or a
#      real `git push --force origin main`, and — because it scans the
#      neutralised copy — does NOT block `grep -rn "rm -rf" .`,
#      `git commit -m "docs: explain rm -rf policy"`, `rg "git push -f" ...`,
#      `jq '.cmd = "rm -rf /x"' a.json`, etc. Those only CONTAIN the text as
#      quoted data; once neutralised it reads as harmless '#' filler.
#   2) payload pass — see check_payloads below. For a segment whose command is
#      an executor, the quoted argument it will RUN is re-checked as a command
#      in its own right, with these same anchors.
#
# Widening the anchors so a quote counts as a word boundary was tried and
# reverted: it turns "quoted text mentioning rm/git" into a false block for
# every command that merely contains that text as data — `grep -rn "rm -rf" .`,
# `rg "git push -f"`, `echo`, `jq`, a commit message. Measured: 5 new false
# positives for 1 extra catch. Recursion gets the catch without the cost.
ORIG_LEAD='(^|[[:space:];&|])'
ORIG_BOUNDARY='([[:space:]]|$)'

check_destructive() {
	local c=$1 lead=$2 bound=$3
	if [[ "$c" =~ ${lead}rm[[:space:]]+(-[a-zA-Z]*[rR][a-zA-Z]*f|-[a-zA-Z]*f[a-zA-Z]*[rR]|-r[[:space:]]+-f|-f[[:space:]]+-r) ]] \
		&& [[ ! "$c" =~ /tmp/backup/ ]]; then
		block "recursive force-delete" \
"Never delete files — rename with a 'backup_' prefix into /tmp/backup/<project>/.
A real deletion needs an explicit 'yes' from the user first."
	fi

	if [[ "$c" =~ git[[:space:]].*push.*(--force([^-]|$)|[[:space:]]-f${bound}) ]]; then
		block "git push --force" \
"Force-push rewrites published history. Use --force-with-lease and get explicit
user approval first (skill git-flow)."
	fi

	# reset --hard, clean -fd, restore, stash drop/clear, and the two discard
	# forms of checkout. Branch switching ('checkout main', 'checkout -b feat')
	# stays allowed.
	if [[ "$c" =~ git[[:space:]]+(reset[[:space:]]+--hard|clean[[:space:]]+-[a-zA-Z]*[dfx]|restore${bound}|stash[[:space:]]+(drop|clear)) ]] \
		|| [[ "$c" =~ git[[:space:]]+checkout[[:space:]]+\.${bound} ]] \
		|| [[ "$c" =~ git[[:space:]]+checkout([[:space:]]+[^[:space:]-][^[:space:]]*)*[[:space:]]+--${bound} ]]; then
		block "git working-tree rollback" \
"Rollbacks require an explicit 'yes' from the user. Default is to COMMIT what
exists, even if the diff looks trivial. Ask before discarding."
	fi

	if [[ "$c" =~ git[[:space:]]+worktree[[:space:]]+remove.*--force ]]; then
		block "git worktree remove --force" \
"This is an rm -rf of the worktree and destroys untracked files. Run
'git status --porcelain' on it first and move anything untracked to /tmp/backup/."
	fi
}

check_destructive "$scan_cmd" "$ORIG_LEAD" "$ORIG_BOUNDARY"

# Executors: things that run a quoted argument as a real command.
EXEC_RE="${CMD}"'(make([[:space:]]|$)|(sh|bash|zsh)[[:space:]]+-c([[:space:]]|$)|eval([[:space:]]|$)|xargs([[:space:]]|$)|docker[[:space:]]+exec([[:space:]]|$)|docker[[:space:]]+compose[[:space:]]+(run|exec)([[:space:]]|$))'

# check_payloads recurses ONE level: it pulls the quoted argument an executor
# will run and re-checks it AS A COMMAND, with the ordinary anchors. That is
# why no widened, quote-inclusive anchor is needed anywhere — inside a payload
# the destructive verb sits at position 0, which the original anchors already
# match.
#
# Only two shapes are treated as a payload, because everything else quoted in
# an executor's argv belongs to some INNER tool, not to the executor:
#   -c "<payload>"    sh/bash/zsh -c, and
#   NAME="<payload>"  a make/docker variable assignment.
# `xargs grep "rm -rf"` is deliberately NOT a payload: the quoted text is
# grep's pattern, and the default neutralised pass already reads it as inert.
#
# The payload's own inner quotes are neutralised before the check, so
# `sh -c "grep -rn 'rm -rf' ."` recurses to `grep -rn '######' .` and stays
# allowed, while `make run CMD="rm -rf /x"` recurses to a bare `rm -rf /x`
# and blocks.
check_payloads() {
	local s=$1 len=${#1} i=0 c q start content pre
	while (( i < len )); do
		c=${s:i:1}
		if [[ "$c" == "'" || "$c" == '"' ]]; then
			q=$c; start=$((i + 1)); (( i++ ))
			while (( i < len )) && [[ "${s:i:1}" != "$q" ]]; do
				[[ "$q" == '"' && "${s:i:1}" == '\' ]] && (( i++ ))
				(( i++ ))
			done
			content=${s:start:i-start}
			pre=${s:0:start-1}
			# The -c must belong to a SHELL. A bare `-c` test would collide with
			# `grep -c "rm -rf" f`, where -c is grep's count flag and the quote
			# is its pattern — data, not a payload.
			if [[ "$pre" =~ (^|[[:space:]])(sh|bash|zsh)[[:space:]]+-c[[:space:]]*$ ]] \
				|| [[ "$pre" =~ [A-Za-z_][A-Za-z0-9_]*=$ ]]; then
				check_destructive "$(neutralize_quotes "$content")" \
					"$ORIG_LEAD" "$ORIG_BOUNDARY"
			fi
		fi
		(( i++ ))
	done
}

# Payload extraction runs PER SEGMENT, and only for a segment whose own command
# is an executor. Segment-wide would false-positive on `make help | grep -c
# "rm -rf"`: the `-c` there is grep's count flag in a different segment, and
# only the segment boundary tells the two apart. Splitting uses $scan_cmd
# offsets — neutralize_quotes preserves length, so a separator surviving in the
# neutralised copy is a real, unquoted one at the same index in $cmd.
seg_start=0
for (( p = 0; p <= ${#scan_cmd}; p++ )); do
	sep=${scan_cmd:p:1}
	if (( p == ${#scan_cmd} )) || [[ "$sep" == [';&|'] || "$sep" == $'\n' ]]; then
		seg_scan=${scan_cmd:seg_start:p-seg_start}
		[[ "$seg_scan" =~ $EXEC_RE ]] && check_payloads "${cmd:seg_start:p-seg_start}"
		seg_start=$((p + 1))
	fi
done

# --- 3. Docker driven directly ----------------------------------------------
# Blocked: lifecycle verbs. Allowed: config, ps, port, logs, top, images, inspect,
# version, stats — read-only inspection needs no target.
# Scans $scan_cmd (quote-neutralised), NOT $cmd — see the note above CMD/BIN.
if [[ "$scan_cmd" =~ ${CMD}docker[-[:space:]]+compose[[:space:]]+(up|down|build|create|start|stop|restart|kill|rm|run|exec|cp|pull|push|scale|watch|wait) ]] \
	|| [[ "$scan_cmd" =~ ${CMD}docker[[:space:]]+(run|exec|build|create|start|stop|restart|kill|rm|rmi|cp|commit|push|update|prune)([[:space:]]|$) ]] \
	|| [[ "$scan_cmd" =~ ${CMD}docker[[:space:]]+(volume|network|system|image|container|builder)[[:space:]]+(rm|prune|create) ]]; then
	block "direct docker / docker compose command" \
"The stack is never driven by docker directly. $via_make
Read-only 'docker ps|logs|inspect|stats' and 'docker compose config|ps|port|logs'
stay allowed."
fi

# --- 4. Host toolchain instead of the container -----------------------------
# Global rule: Docker only, never a bare host toolchain. Each stack's entry point
# is a make target that runs the tool inside the project's image.
# Scans $scan_cmd (quote-neutralised), NOT $cmd — see the note above CMD/BIN.
if [[ "$scan_cmd" =~ ${CMD}(pip|pip3|uv|poetry|pdm)[[:space:]]+(pip[[:space:]]+)?(install|add|remove|sync|lock|run|venv) ]] \
	|| [[ "$scan_cmd" =~ ${CMD}(npm|yarn|pnpm|bun)[[:space:]]+(install|i|ci|add|remove|update|run|build|start|test|exec) ]] \
	|| [[ "$scan_cmd" =~ ${CMD}npx[[:space:]] ]] \
	|| [[ "$scan_cmd" =~ ${CMD}composer[[:space:]]+(install|update|require|remove|dump-autoload) ]]; then
	block "direct dependency install / package-manager run" \
"Dependencies belong in the container image, not on the host. $via_make"
fi

if [[ "$scan_cmd" =~ ${CMD}${BIN}(pytest|tox|nox|ruff|mypy|black|isort|flake8|pylint|alembic|uvicorn|gunicorn|celery)([[:space:]]|$) ]] \
	|| [[ "$scan_cmd" =~ ${CMD}python3?[[:space:]]+-m[[:space:]]+(pytest|ruff|mypy|black|flake8|alembic|uvicorn|celery|http\.server) ]] \
	|| [[ "$scan_cmd" =~ ${CMD}${BIN}(phpunit|pest|phpstan|psalm|php-cs-fixer|rector)([[:space:]]|$) ]] \
	|| [[ "$scan_cmd" =~ ${CMD}php[[:space:]]+(artisan|-S)([[:space:]]|$) ]] \
	|| [[ "$scan_cmd" =~ ${CMD}${BIN}(jest|vitest|eslint|prettier|tsc|vite|webpack|nest)([[:space:]]|$) ]] \
	|| [[ "$scan_cmd" =~ ${CMD}go[[:space:]]+(build|run|test|install|generate|mod)([[:space:]]|$) ]] \
	|| [[ "$scan_cmd" =~ ${CMD}(mysql|mariadb|psql|mongosh|redis-cli|keydb-cli)([[:space:]]|$) ]]; then
	block "bare host toolchain call" \
"This runs on the host, against the wrong environment — wrong interpreter
version, missing extensions, no service network. $via_make"
fi

# --- 5. Web servers and process supervisors ---------------------------------
# `nginx -v/-V` is a version print and stays allowed; everything else drives a
# running service. Read-only `systemctl status|list-units` stays allowed too.
# Scans $scan_cmd (quote-neutralised), NOT $cmd — see the note above CMD/BIN.
if { [[ "$scan_cmd" =~ ${CMD}(nginx|apache2ctl|apachectl|httpd|php-fpm|supervisorctl|certbot)([[:space:]]|$) ]] \
	&& [[ ! "$scan_cmd" =~ ${CMD}nginx[[:space:]]+-[vV]([[:space:]]|$) ]]; } \
	|| [[ "$scan_cmd" =~ ${CMD}systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask) ]]; then
	block "web server / service control from the host" \
"Services here are containers, not host daemons — a host nginx/php-fpm/systemctl
call hits the wrong thing or nothing at all. $via_make
Host-level service control that genuinely needs root goes to the user as a
ready-to-paste command instead."
fi

exit 0
