---
name: agent-config-test
description: >
  Test that an agent's configuration actually behaves as written — run hook
  scripts against block/allow cases and lint settings.json permission rules and
  hook registration. Use after editing a guard hook, permission allow/ask/deny
  list, hook matcher, or MCP enable list, and when a hook silently never fires
  or a guard blocks a harmless command.
when_to_use: >
  Use when writing or changing a PreToolUse guard, permission rules, or hook
  registration in settings.json / settings.local.json; when a hook does not
  appear to run; when a guard produces a false positive; or when auditing an
  agent config for silent misconfiguration.
allowed-tools: Read Glob Grep Bash Write Edit WebFetch
---

# Test agent configuration

`setup-claude` **writes** agent config. This skill **proves it behaves**.

Two lanes, because only one of them is executable:

| Lane | Tool | What it proves |
|---|---|---|
| Hook behaviour | `test-hooks.sh` | Real assertion: this payload => this exit code |
| Settings shape | `lint-settings.sh` | Static only. It never proves a `deny` rule works |

There is no evaluator for `allow`/`ask`/`deny` rules — nothing to shell out to.
Never report permission rules as "tested"; they are linted.

## Happy path

```bash
skills/agent-config-test/test-hooks.sh  .claude/hooks/guard-bash.sh  cases/guard-bash.tsv
skills/agent-config-test/lint-settings.sh  /path/to/project
```

Cases file — `<expected-exit>TAB<command>[TAB<label>]`, `2` = must block, `0` =
must allow, `\n` decodes to a real newline. Start from
[cases/guard-bash.tsv](cases/guard-bash.tsv) and keep its bypass block verbatim.

Other events: `--event PostToolUse --tool Edit`, or put raw JSON in the payload
column (any line starting with `{`). Per-event stdin fields and valid matcher
values → [reference.md](reference.md).

`test-hooks.sh` maps the plain-text payload column into the right
`tool_input` field by tool: `command` for Bash/PowerShell, `file_path` for
Read/Edit/Write, `path` for Grep/Glob, `notebook_path` for NotebookEdit, `url`
for WebFetch — with an explicit `--field NAME` override for anything else. For
a file-path hook (e.g. a lint gate on `Edit`), see
[cases/check-file.tsv](cases/check-file.tsv).

## The three rules that make this worth running

**1. Test BOTH directions, always.** Block-cases alone certify a guard that also
eats `grep -rn pytest tests/`. Every real bug found in these guards was a false
positive: `dd` matching inside `add`, `rm` inside `confirm`. A suite without
must-allow cases is worse than no suite — it manufactures confidence.

**2. Cases live in a FILE, never on the command line.** A guard matches command
TEXT, so a runner invoked as `for c in "docker compose up" ...` trips the very
guard under test and the suite blocks itself. This is not hypothetical; it is
the first thing that happens.

**3. Cover the bypass classes.** Every command-text guard leaks the same four
ways. Keep all of them in every suite:

| Class | Example | Why it slips |
|---|---|---|
| Newline | `cd /x\ndocker compose up` | bash `^` anchors to string start, not line start |
| Assignment prefix | `FOO=1 docker compose up` | anchor expects the verb at position 0 |
| Wrapper prefix | `env FOO=1 pytest`, `sudo docker …` | same |
| Quoting / args | `grep -rn pytest tests/` | the false-positive direction |

Anchoring at *any whitespace* fixes 4 and opens 1-3. Anchoring at bare `^` fixes
1-3 and opens 4. The shape that survives all four is in
[hooks/guard-bash.sh](../../hooks/guard-bash.sh) — copy the `CMD=` line.

## A green suite does not mean the hook is live

`test-hooks.sh` executes the script directly. That proves the *logic*; it proves
nothing about whether the harness is calling it. Registration is a separate
failure surface — invalid matcher, wrong settings file, plugin not reloaded.

Finish with a **liveness probe**: run one command the hook must block, and check
the block message names the hook you expect. Pick a probe that is harmless if it
actually executes (`pytest --version`, `nginx -t`), and one that no *other*
guard already covers — otherwise a project hook answers first and the one you
are testing stays unproven.

Traps this catches:

- **Plugin hooks are registered at session start; skills are not.** After
  syncing a plugin, its new skill shows up immediately while its `hooks.json`
  keeps running the old registration until a new session. Seeing the skill in
  the list is not evidence the hook is live — verified 2026-08-15, where a
  freshly synced global guard let `nginx -t` straight through in the same
  session that already listed its skill.
- Two guards registered for the same event both run; the first to exit 2 wins,
  so a broad project hook masks whatever you were trying to prove about a
  global one.

## What lint-settings.sh catches

Each of these has silently broken a real config:

- Invalid JSON in `settings.json` / `settings.local.json` — every other check
  is skipped for that file, so this fires first and alone.
- `matcher` invalid for the event → **the hook never fires, with no error**.
  `SessionStart` takes `startup|resume|clear|compact|fork`; `"*"` is not a
  wildcard here. `Stop`, `UserPromptSubmit` and others take no matcher at all.
  Also enumerated: `Notification`, `DirectoryAdded`, `StopFailure`.
- An `allow` rule with an unbalanced quote — `Bash(python3 -c ' *)` has one
  `'`, so the quote never closes and the trailing `*` (which spans spaces)
  auto-approves every one-liner python3 can run. A rule with a *closed* quote,
  `Bash(echo "hello" *)`, does not trigger this — the check counts `'` and `"`
  separately and only fires on an odd count.
- A **deny/ask** rule matching a tool's primary content field —
  `Bash(command:rm *)`, `Read(file_path:...)` — is bypassable by a compound
  command, so Claude Code ignores it entirely and warns at startup. Write
  `Bash(rm *)` / `Read(./path)` instead. The same text as an **allow** rule is
  a different, dead-er mistake: allow rules never support parameter matching
  at all, so `Bash(command:rm *)` is a literal command-text glob matching
  commands that start with `command:rm ` — nothing real does.
- An unanchored tool-name glob in `allow` — `"*"`, `"B*"`, `"mcp__*"` — is
  skipped with a warning and auto-approves nothing. Allow rules only accept a
  glob after a literal `mcp__<server>__` prefix with a glob-free server.
- A trailing `*` glued directly to the prefix with no space — `Bash(ls*)` —
  skips the word-boundary check and also matches `lsof`.
- A mid-pattern `:*` — `Bash(git:* push)` — is dead: `:*` is only a trailing
  wildcard at the very end of a pattern, so elsewhere the colon is literal and
  the rule matches nothing real.
- An `allow` rule on a development environment runner (`direnv exec`,
  `devbox run`, `mise exec`, `npx`, `docker exec`) with a trailing wildcard —
  these execute their arguments as a command, so `Bash(devbox run *)` also
  approves `devbox run rm -rf .`.
- A broad `deny` masking a narrower `allow` — `deny` is absolute, so
  `deny: Bash(docker compose *)` + `allow: Bash(docker compose config *)` loses
  the allow. Enumerate the denied verbs instead. Fires on both wildcard forms,
  and only when the allow's content is the deny's prefix exactly or that
  prefix followed by a space — the same word-boundary rule as `Bash(ls*)`
  above, so `deny: Bash(git push *)` does NOT falsely mask an unrelated
  `allow: Bash(git pushover status)`.
- `deny` on a whole namespace whose read-only verbs you still need — the
  message names the actual read-only subcommand per namespace (`docker volume
  ls`/`inspect`, `docker network ls`/`inspect`, `docker system df`/`info`,
  `docker image ls`/`inspect`) since `deny` cannot be approved past.
- Hook script referenced but missing or not executable.
- `settings.local.json` diverging from `settings.json` — local outranks tracked,
  so a stale local list silently masks what the repo declares.

### The space form is correct, not a typo

`Bash(cmd *)` is what the permission dialog itself writes when you pick "Yes,
don't ask again" for a command prefix — it is the primary documented shape,
not a mistaken glob. `Bash(cmd:*)` is only an equivalent trailing-wildcard
suffix, and is recognized **solely at the end** of a pattern (`Bash(git:*
push)` treats the colon as a literal character). A single `*` matches any
sequence of characters *including spaces*, so one wildcard can span multiple
arguments. `Bash(cmd *)` (space before `*`) enforces a word boundary — it
matches `cmd -x` but not `cmdfoo`; `Bash(cmd*)` (no space) does not. Do not
re-add a check that flags the space form as a mistake — see
`lint-settings.sh`'s header for the source page.

### Baseline first — a lint-gate hook needs a known-GREEN target

Before asserting on a **lint-gate hook** (a hook that runs a linter/formatter
over the edited file), establish the baseline by running that same check
against the untouched file first. A must-allow case has to target a file
known-GREEN at baseline — otherwise both "blocks" and "allows" are
uninformative in an already-red repo, and the run reports a working hook as a
false positive (or the reverse). Real case, 2026-08-15, courierist: a
PostToolUse PHPCS hook blocked every edit to `src/Kernel.php` because that
file already had 4 pre-existing errors; the gate was unusable, not misfiring.

## Safety

- The linter and runner only read config and execute the hook under test. They
  change nothing.
- A hook under test may have side effects of its own — read it before running a
  suite against it.
- `exit 2` is the block signal for `PreToolUse`; for most other events it means
  something else entirely (`Stop` = do not stop, `PreCompact` = block compaction,
  and several events ignore the exit code). Check reference.md before asserting
  on an exit code for an event you have not tested before.
