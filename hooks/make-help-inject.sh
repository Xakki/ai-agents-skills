#!/usr/bin/env bash
# SessionStart: inject `make help` so the Makefile is the command reference.
#
# Policy (global): every project has a Makefile and every build/run/test/deploy
# operation goes through a make target. This hook makes that list always-present,
# so no doc anywhere duplicates a need->target table.
#
# No `matcher` key on this hook's registration: SessionStart accepts only
# startup|resume|clear|compact|fork, and an invalid matcher such as "*" makes the
# hook silently never fire.
set -u

dir=${CLAUDE_PROJECT_DIR:-$PWD}

# Not a project root (no VCS, no manifest) => stay quiet; nagging in a scratch
# dir or $HOME is noise, not enforcement.
is_project() {
	[ -d "$dir/.git" ] && return 0
	for m in package.json composer.json go.mod pyproject.toml Cargo.toml pom.xml; do
		[ -f "$dir/$m" ] && return 0
	done
	return 1
}

if [ ! -f "$dir/Makefile" ] && [ ! -f "$dir/makefile" ]; then
	is_project || exit 0
	cat <<-EOF
	# No Makefile in this project

	Policy: **every project has a Makefile**, and everything that touches a
	service, container or language runtime goes through \`make <target>\` —
	build, up/down, test, lint, migrate, deploy. Plain shell (ls, grep, sed,
	git, curl…) needs no target and is unaffected.

	There is none here. Create one — a \`help\` target plus a one-line \`##\`
	description per target — before driving docker or a toolchain directly.
	EOF
	exit 0
fi

out=$(cd "$dir" && timeout 15 make -s --no-print-directory help 2>/dev/null \
	| sed $'s/\x1b\\[[0-9;]*m//g') || exit 0

if [ -z "$out" ]; then
	printf '# Makefile has no `help` target\n\nAdd one (awk over `##` comments) so `make help` lists targets.\n'
	exit 0
fi

cat <<EOF
# Project commands — \`make help\` (auto-injected)

RULE — scope is services, containers and language runtimes: docker/compose,
package managers, python/php/node/go toolchains, DB clients, web servers. Those
go through a make target. Plain shell (ls, grep, find, sed, awk, jq, curl, tar,
git) is NOT in scope — run it directly, do not invent a target for it.

Missing target for something in scope => ADD it to the Makefile, then use it.
One target per operation, no near-duplicates. A one-line \`##\` description,
terse, standard abbreviations — this output is always in context, so every char
is a per-session tax. Recipes read without comments; comment only a non-obvious
flag or a workaround. Output unclear => fix the \`##\` description, never
duplicate the list in docs.

${out:0:12000}
EOF
