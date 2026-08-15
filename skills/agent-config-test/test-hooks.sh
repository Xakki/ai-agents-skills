#!/usr/bin/env bash
# Universal hook behaviour test runner.
#
#   test-hooks.sh <hook-script> <cases.tsv> [--event EVENT] [--tool TOOL] [--field NAME]
#
# Cases file: one case per line, TAB-separated.
#     <expected-exit><TAB><payload>[<TAB><label>]
#   expected-exit  0 = must be allowed, 2 = must be blocked (any int works)
#   payload        a plain-text value, or raw JSON when it starts with '{'
#   \n in a command is decoded to a real newline (multi-line command cases)
# Blank lines and lines starting with # are skipped.
#
# A plain-text payload is wrapped into tool_input as ONE field, chosen by
# --tool (override with --field NAME for a hook that reads something else):
#   command        Bash, PowerShell
#   file_path      Read, Edit, Write
#   path           Grep, Glob
#   notebook_path  NotebookEdit
#   url            WebFetch
#   command        anything else (default)
# Raw-JSON payloads (leading '{') pass through untouched — no field mapping.
#
# The cases live in a FILE on purpose: a guard hook matches command TEXT, so
# passing cases on the command line makes the runner's own invocation trip the
# very guard under test.
set -uo pipefail

usage() { sed -n '2,25p' "$0" >&2; exit 64; }

hook=${1:-}
cases=${2:-}
shift 2 2>/dev/null || true
event=PreToolUse
tool=Bash
field=
while [ $# -gt 0 ]; do
	case "$1" in
	--event) [ $# -ge 2 ] || usage; event=$2; shift 2 ;;
	--tool) [ $# -ge 2 ] || usage; tool=$2; shift 2 ;;
	--field) [ $# -ge 2 ] || usage; field=$2; shift 2 ;;
	*) echo "unknown arg: $1" >&2; exit 64 ;;
	esac
done

if [ -z "$hook" ] || [ -z "$cases" ]; then
	usage
fi
[ -x "$hook" ] || { echo "not executable: $hook" >&2; exit 64; }
[ -r "$cases" ] || { echo "unreadable: $cases" >&2; exit 64; }

if [ -z "$field" ]; then
	case "$tool" in
	Bash | PowerShell) field=command ;;
	Read | Edit | Write) field=file_path ;;
	Grep | Glob) field=path ;;
	NotebookEdit) field=notebook_path ;;
	WebFetch) field=url ;;
	*) field=command ;;
	esac
fi
printf '%s  event=%s tool=%s field=%s\n' "$(basename "$hook")" "$event" "$tool" "$field"

pass=0 fail=0

payload_json() { # $1 = payload
	if [ "${1:0:1}" = "{" ]; then
		printf '%s' "$1"
	else
		jq -nc --arg c "$1" --arg e "$event" --arg t "$tool" --arg d "$PWD" --arg f "$field" \
			'{hook_event_name:$e, tool_name:$t, cwd:$d, session_id:"test",
			  transcript_path:"/dev/null", tool_input:{($f):$c}}'
	fi
}

while IFS=$'\t' read -r want payload label; do
	[ -z "${want:-}" ] && continue
	case "$want" in \#*) continue ;; esac
	payload=${payload//\\n/$'\n'}

	got=0
	payload_json "$payload" | "$hook" >/dev/null 2>&1 || got=$?

	if [ "$got" = "$want" ]; then
		pass=$((pass + 1))
		[ -n "${VERBOSE:-}" ] && printf 'ok   %s  %s\n' "$got" "${label:-$payload}"
	else
		fail=$((fail + 1))
		printf 'FAIL want=%s got=%s  %s\n' "$want" "$got" "${label:-$payload}"
	fi
done <"$cases"

printf '\n%s: %d passed, %d failed\n' "$(basename "$hook")" "$pass" "$fail"
[ "$fail" -eq 0 ]
