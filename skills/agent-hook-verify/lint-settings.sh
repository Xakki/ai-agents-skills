#!/usr/bin/env bash
# Static checks on Claude Code settings files.
#
#   lint-settings.sh [project-dir]
#
# Checks what cannot be tested behaviourally: permission-rule shape and hook
# registration. Hook BEHAVIOUR is tested separately by test-hooks.sh — this
# script never proves a deny rule works, only that it is shaped sanely.
#
# Permission-rule checks source: code.claude.com/docs/en/permissions. Verify
# against it before relying on one of these checks; on drift, fix this file
# in the same change and report it. Each check below cites the doc section
# anchor it comes from (#wildcard-patterns, #bash, #compound-commands,
# #match-by-input-parameter, #tool-name-wildcards, #manage-permissions).
# Hook-registration checks source — see reference.md's own header.
#
# Exit 0 = clean, 1 = findings. Findings print as: LEVEL  file  message
set -uo pipefail

dir=${1:-${CLAUDE_PROJECT_DIR:-$PWD}}
found=0

say() { printf '%-5s %-28s %s\n' "$1" "$2" "$3"; [ "$1" = WARN ] && found=1; return 0; }

# Events that accept NO matcher, and events with an enumerated matcher set.
# Source: code.claude.com/docs/en/hooks, "Each event type matches on a
# different field" table (see reference.md). TeammateIdle was missing from
# no_matcher and Notification/DirectoryAdded/StopFailure were missing from
# enum_matcher — reconciled against the doc's raw HTML 2026-08-15.
no_matcher='UserPromptSubmit Stop PostToolBatch TaskCreated TaskCompleted MessageDisplay CwdChanged WorktreeCreate WorktreeRemove TeammateIdle'
declare -A enum_matcher=(
	[SessionStart]='startup resume clear compact fork'
	[Setup]='init maintenance'
	[PreCompact]='manual auto'
	[PostCompact]='manual auto'
	[SessionEnd]='clear resume logout prompt_input_exit bypass_permissions_disabled other'
	[ConfigChange]='user_settings project_settings local_settings policy_settings skills'
	[InstructionsLoaded]='session_start nested_traversal path_glob_match include compact'
	[Notification]='permission_prompt idle_prompt auth_success elicitation_dialog elicitation_url_dialog elicitation_complete elicitation_response agent_needs_input agent_completed'
	[DirectoryAdded]='slash_command register_repo_root'
	[StopFailure]='rate_limit overloaded authentication_failed oauth_org_not_allowed billing_error invalid_request model_not_found server_error max_output_tokens unknown'
)

# Primary content field per tool — Claude Code ignores an input-parameter
# rule written against these, since a compound command would bypass it.
# Source: #match-by-input-parameter.
declare -A primary_field=(
	[Bash]=command
	[PowerShell]=command
	[Read]=file_path
	[Edit]=file_path
	[Write]=file_path
	[Grep]=path
	[Glob]=path
	[NotebookEdit]=notebook_path
	[WebFetch]=url
)

# Development environment runners whose arguments run as a command, so a
# trailing-wildcard allow rule approves whatever follows the runner verb.
# Source: #compound-commands.
runner_prefixes=('direnv exec' 'devbox run' 'mise exec' 'npx' 'docker exec')

# Read-only verb(s) a deny on this docker namespace also blocks. Not a doc
# citation — plain docker CLI knowledge, kept accurate per namespace instead
# of one generic "ls/df" claim (df is a docker-system-only subcommand).
declare -A docker_ns_readonly=(
	['docker volume']="'docker volume ls' / 'docker volume inspect'"
	['docker network']="'docker network ls' / 'docker network inspect'"
	['docker system']="'docker system df' / 'docker system info'"
	['docker image']="'docker image ls' / 'docker image inspect'"
)

lint_file() {
	local f=$1 short=$2
	[ -r "$f" ] || return 0
	jq -e . "$f" >/dev/null 2>&1 || { say WARN "$short" "invalid JSON"; return 0; }

	# --- permission rule shape ---
	# Regexes held in vars: an unescaped ')' inside a bracket expression breaks
	# bash's parser when written inline in [[ =~ ]].
	#
	# The space-separated form (`Bash(cmd *)`) is not a mistaken glob — it is
	# what the permission dialog itself writes for "Yes, don't ask again", and
	# is the primary documented shape. `:*` is only an equivalent trailing-
	# wildcard suffix, recognized solely at the END of a pattern. Source:
	# #wildcard-patterns — "The permission dialog writes the space-separated
	# form... The `:*` form is only recognized at the end of a pattern."
	local list rule
	# Trailing `*` with no space before it skips the word-boundary check, so
	# `Bash(ls*)` also matches `lsof`. Only fires on a TRAILING `*` that abuts
	# a non-space, non-colon char — `Bash(git * main)` and `Bash(* --version)`
	# end in something other than `*)` and never match this. Source: #bash —
	# "When `*` appears at the end with a space before it..., it enforces a
	# word boundary... In contrast, `Bash(ls*)` without a space matches both
	# `ls -la` and `lsof`."
	local no_boundary='^(Bash|PowerShell)\([^)]*[^:[:space:]]\*\)$'
	# Deny/ask rules CAN match a top-level input parameter (`Tool(param:val)`),
	# but never the tool's primary content field — Claude Code ignores such a
	# rule and warns at startup because a compound command bypasses it. Allow
	# rules never get this feature at all: "allow rules continue to use each
	# tool's own specifier syntax" (own quote, #match-by-input-parameter), so
	# `Bash(command:rm *)` as an ALLOW rule isn't parameter matching that got
	# ignored — it's a literal command-text glob matching commands that start
	# with the literal text "command:rm ", i.e. dead config matching nothing
	# real. Source: #match-by-input-parameter — "A rule like
	# `Bash(command:rm *)` would be bypassable by a compound command, so
	# Claude Code ignores it and emits a startup warning" (deny/ask context)
	# and "An allow rule for one parameter value wouldn't establish that the
	# call is safe overall, so allow rules continue to use each tool's own
	# specifier syntax" (why allow never had this feature to begin with).
	local input_param_re='^([A-Za-z_][A-Za-z0-9_]*)\(([a-zA-Z_][a-zA-Z0-9_]*):'
	while IFS=$'\t' read -r list rule; do
		[ -z "$rule" ] && continue

		# Unbalanced quote in a Bash allow rule: an odd count of `'` or `"` in
		# the inner content means a quote is left open, so everything after it
		# — including a trailing `*` — runs inside the quote and is unbounded.
		# `Bash(echo "hello" *)` and `Bash(git commit -m "wip" *)` both have an
		# EVEN quote count (closed) and must NOT fire. Source: #bash — "A
		# single `*` matches any sequence of characters including spaces, so
		# one wildcard can span multiple arguments."
		if [ "$list" = allow ] && [[ "$rule" == 'Bash('*')' ]]; then
			local inner=${rule#Bash(}
			inner=${inner%)}
			local sq=${inner//[^\']/} dq=${inner//[^\"]/}
			if (( ${#sq} % 2 != 0 )) || (( ${#dq} % 2 != 0 )); then
				say WARN "$short" "unbalanced quote in '$rule' — an odd number of quote characters means a quote is left open, so everything after it (including a trailing *) runs inside the quote; pin the exact command or fix the quoting"
			fi
		fi

		if [ "$list" = allow ] && [[ "$rule" =~ $no_boundary ]]; then
			say WARN "$short" "no word boundary in '$rule' — a trailing * with no space before it also matches unrelated commands sharing the prefix (e.g. cmd* matches cmdfoo too); write it as 'cmd *' or 'cmd:*'"
		fi

		if [ "$list" = allow ]; then
			for r in "${runner_prefixes[@]}"; do
				if [ "$rule" = "Bash($r *)" ] || [ "$rule" = "Bash($r:*)" ]; then
					say WARN "$short" "environment-runner rule '$rule' — '$r' executes its arguments as a command, so this approves everything after it (e.g. '$r rm -rf .'); write one exact-match rule per inner command instead"
				fi
			done
		fi

		# Mid-pattern `:*` (not at the very end) is a dead rule: the colon is
		# literal there, so it matches nothing real. Source: #wildcard-patterns
		# — "In a pattern like `Bash(git:* push)`, the colon is treated as a
		# literal character and won't match git commands."
		if [[ "$rule" == *':*'* && "$rule" != *':*)' ]]; then
			say WARN "$short" "mid-pattern ':*' in '$rule' — ':*' is only a trailing wildcard at the very end of a pattern; elsewhere the colon is literal, so this matches nothing real"
		fi

		if [[ "$rule" =~ $input_param_re ]]; then
			local tool=${BASH_REMATCH[1]} field=${BASH_REMATCH[2]}
			if [ "${primary_field[$tool]:-}" = "$field" ]; then
				if [ "$list" = allow ]; then
					say WARN "$short" "'$rule' is not input-parameter matching — allow rules only ever use $tool's own specifier syntax, so this is a literal command-text glob matching commands starting with the literal text '$field:...', which is dead config matching nothing real; write $tool's own specifier instead (e.g. Bash(rm *), Read(./path), WebFetch(domain:host))"
				else
					say WARN "$short" "'$rule' matches on $tool's primary content field ($field) — Claude Code ignores this and warns at startup; use $tool's own specifier syntax instead (e.g. Bash(rm *), Read(./path), WebFetch(domain:host))"
				fi
			fi
		fi
	done < <(jq -r '.permissions // {} | to_entries[] | select(.key | IN("allow","ask","deny")) | .key as $k | .value[]? | [$k, .] | @tsv' "$f")

	# --- unanchored tool-name glob in allow (matches nothing) ---
	# Allow rules accept a tool-name glob only after a literal `mcp__<server>__`
	# prefix with a glob-free server segment. Anything else — "*", "B*",
	# "mcp__*" — is skipped with a warning and auto-approves nothing.
	# Source: #tool-name-wildcards — "An unanchored allow glob such as `\"*\"`,
	# `\"B*\"`, or `\"mcp__*\"` is skipped with a warning and doesn't
	# auto-approve anything."
	local a
	while IFS= read -r a; do
		[ -z "$a" ] && continue
		[[ "$a" == *'('* ]] && continue
		[[ "$a" == *'*'* ]] || continue
		if [[ "$a" == mcp__* ]]; then
			local rest=${a#mcp__}
			local server=${rest%%__*}
			[[ "$server" == *'*'* || "$rest" != *'__'* ]] && \
				say WARN "$short" "unanchored tool-name glob '$a' in allow — allow rules only accept a glob after a literal mcp__<server>__ prefix with a glob-free server; write mcp__<server>__* instead"
		else
			say WARN "$short" "unanchored tool-name glob '$a' in allow — matches nothing; allow rules don't accept a bare tool-name glob outside mcp__<server>__*"
		fi
	done < <(jq -r '.permissions.allow // [] | .[]' "$f")

	# --- broad deny masking a narrower allow ---
	# deny is absolute: a narrower allow beneath a broad deny never wins. Covers
	# both trailing-wildcard forms — `Bash(aws:*)` and `Bash(aws *)` — since
	# they are equivalent. Source: #manage-permissions — "A broad deny rule
	# like `Bash(aws *)` blocks every matching call, including calls that also
	# match a narrower allow rule like `Bash(aws s3 ls)`."
	#
	# Applies the SAME word-boundary rule as #bash's `ls *` vs `lsof`: an allow
	# only counts as masked when its inner content equals the deny's inner
	# prefix, or starts with that prefix followed by a space. A raw bash-glob
	# prefix test (no boundary) reports deny `Bash(git push *)` as masking
	# allow `Bash(git pushover status)` — an unrelated command the deny would
	# never actually block.
	local d a dinner ainner
	while IFS= read -r d; do
		[ -z "$d" ] && continue
		if [[ "$d" == *':*)' ]]; then
			dinner=${d%:\*)}
		elif [[ "$d" == *' *)' ]]; then
			dinner=${d% \*)}
		else
			continue
		fi
		dinner=${dinner#Bash(}
		while IFS= read -r a; do
			[ -z "$a" ] && continue
			[[ "$a" == 'Bash('*')' ]] || continue
			[ "$a" = "$d" ] && continue
			ainner=${a#Bash(}
			ainner=${ainner%)}
			if [ "$ainner" = "$dinner" ] || [[ "$ainner" == "$dinner "* ]]; then
				say WARN "$short" "deny '$d' masks allow '$a' — enumerate the denied verbs instead"
			fi
		done < <(jq -r '.permissions.allow // [] | .[]' "$f")
	done < <(jq -r '.permissions.deny // [] | .[]' "$f")

	# --- deny on a whole namespace whose read-only verbs you will want ---
	# Matches both trailing-wildcard forms for the same namespace. Message is
	# per-namespace (not a generic "ls/df" claim) — `df` is a docker-system-only
	# subcommand, not shared by volume/network/image.
	while IFS= read -r d; do
		for ns in "${!docker_ns_readonly[@]}"; do
			if [ "$d" = "Bash($ns:*)" ] || [ "$d" = "Bash($ns *)" ]; then
				say WARN "$short" "deny '$d' also blocks read-only ${docker_ns_readonly[$ns]} — narrow to rm/prune"
			fi
		done
	done < <(jq -r '.permissions.deny // [] | .[]' "$f")

	# --- hook registration ---
	local ev m cmd path
	while IFS=$'\t' read -r ev m; do
		[ -z "$ev" ] && continue
		if [ "$m" != "null" ] && [ -n "$m" ]; then
			if [[ " $no_matcher " == *" $ev "* ]]; then
				say WARN "$short" "$ev accepts no matcher, but '$m' is set — the hook may never fire"
			elif [ -n "${enum_matcher[$ev]:-}" ]; then
				[[ " ${enum_matcher[$ev]} " == *" $m "* ]] || \
					say WARN "$short" "$ev matcher '$m' is not one of: ${enum_matcher[$ev]} — the hook never fires"
			fi
		fi
	done < <(jq -r '.hooks // {} | to_entries[] | .key as $e | .value[] | [$e, (.matcher // "null")] | @tsv' "$f")

	while IFS= read -r cmd; do
		[ -z "$cmd" ] && continue
		path=${cmd%% *}
		path=${path//\"/}
		path=${path/\$\{CLAUDE_PROJECT_DIR\}/$dir}
		path=${path/\~/$HOME}
		case "$path" in
		*'${CLAUDE_PLUGIN_ROOT}'*) continue ;;
		/*) ;;
		*) continue ;;
		esac
		if [ ! -e "$path" ]; then
			say WARN "$short" "hook script not found: $path"
		elif [ ! -x "$path" ]; then
			say WARN "$short" "hook script not executable: $path"
		fi
	done < <(jq -r '.hooks // {} | to_entries[] | .value[] | .hooks[]? | select(.type=="command") | .command' "$f")
}

lint_file "$dir/.claude/settings.json" "settings.json"
lint_file "$dir/.claude/settings.local.json" "settings.local.json"

# --- local settings masking tracked intent ---
# settings.local.json outranks settings.json, so a stale list there silently
# overrides what the repo declares.
proj="$dir/.claude/settings.json"
loc="$dir/.claude/settings.local.json"
if [ -r "$proj" ] && [ -r "$loc" ]; then
	for key in enabledMcpjsonServers disabledMcpjsonServers; do
		p=$(jq -cS ".$key // empty" "$proj" 2>/dev/null)
		l=$(jq -cS ".$key // empty" "$loc" 2>/dev/null)
		if [ -n "$p" ] && [ -n "$l" ] && [ "$p" != "$l" ]; then
			say WARN "settings.local.json" "$key diverges from settings.json ($l vs $p) — local wins, tracked intent is masked"
		fi
	done
fi

[ "$found" = 0 ] && echo "OK — no findings"
exit "$found"
