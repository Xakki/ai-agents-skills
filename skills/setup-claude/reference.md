# setup-claude — reference

Full detail: doc URLs, frontmatter fields, templates, hooks. Read when you're actually building.

## Doc URLs (WebFetch before writing anything)

| URL | What to read |
|---|---|
| `https://code.claude.com/docs/en/memory` | CLAUDE.md hierarchy, `@import`, `.claude/rules/`, auto-memory |
| `https://code.claude.com/docs/en/sub-agents` | Agent frontmatter, model, tools, skills, mcpServers, isolation |
| `https://code.claude.com/docs/en/skills` | `.claude/skills/<name>/SKILL.md`, frontmatter, progressive disclosure |
| `https://code.claude.com/docs/en/slash-commands` | Legacy `.claude/commands/*.md` (merged into skills) |
| `https://code.claude.com/docs/en/mcp` | `.mcp.json`, scopes, `claude mcp add` |
| `https://code.claude.com/docs/en/settings` | Hierarchy, permissions, enabledMcpjsonServers |
| `https://code.claude.com/docs/en/hooks` | Events, JSON schema, exit codes, matcher |
| `https://code.claude.com/docs/en/common-workflows` | Workflow patterns |
| `https://code.claude.com/docs/en/best-practices` | CLAUDE.md quality, token economy |
| `https://code.claude.com/docs/llms.txt` | Full doc index |

## CLAUDE.md guidance

`./CLAUDE.md` or `./.claude/CLAUDE.md`. Limit: **≤ 200 lines**.

Contains **only what can't be read from code**:
- Project purpose (1–3 lines)
- Stack architecture map
- Commands — link to `make help` + 5–10 key targets in one line
- Team process rules: branches, commits, PRs, deploy, what not to merge
- Protected paths: DB data, secrets, build artifacts
- No-index zones: `vendor/`, `node_modules/`, dumps
- Pointers to TODO/ADR/runbooks
- `@import` of parent `CLAUDE.md` (max 5 hops; paths relative to file)
- If `AGENTS.md` exists: `@AGENTS.md` at top
- Mandatory rule: "All ops via `make <target>`. If target missing — add it, don't run the command directly."

**Principles (from Anthropic docs):**
- **Specificity**: "Use 2-space indentation" not "format code properly"
- Markdown structure: headers and bullets
- HTML comments `<!-- ... -->` at block level are stripped from context — use for maintainer notes without spending tokens
- In monorepos, exclude conflicting ancestor CLAUDE.md via `claudeMdExcludes` in `.claude/settings.local.json`

**Anti-patterns**: folder structure recap, README duplication, framework explanation.

### `.claude/rules/*.md` — path-scoped rules

For large repos. Load only when files match `paths:` frontmatter:

```yaml
---
paths:
  - "src/api/**/*.ts"
---
Rule text here, only loaded when editing matched paths.
```

Without `paths:` — load every session.

## Agent frontmatter fields

```yaml
---
name: code-reviewer            # required, lowercase + hyphens
description: When Claude should delegate here  # required
tools: Read, Glob, Grep, Bash  # comma-separated; omit = inherit all
disallowedTools: Write, Edit   # denylist (applied first)
model: sonnet                  # sonnet|opus|haiku|claude-opus-4-7|inherit
permissionMode: default        # default|acceptEdits|auto|dontAsk|bypassPermissions|plan
maxTurns: 20
skills: [api-conventions]      # preload skill content at startup
mcpServers: [your-mcp-server]
hooks: { ... }
memory: project                # user|project|local
isolation: worktree
effort: medium                 # low|medium|high|xhigh|max
background: false
color: cyan
---
```

Rules:
- `name` + `description` are required
- Use `tools:` (allowlist) **or** `disallowedTools:` (denylist) — not `*`
- `description` written for auto-delegation: "Use when…", "proactively after…"
- Narrow scope — agent returns only a summary
- Include "use `make` targets" instruction in the body

Candidates: `*-explorer` per major stack, `db-schema`, `log-investigator`, `test-runner`, `migration-author`.

## Skill frontmatter fields

```yaml
---
name: prepare-pr                       # /skill-name; lowercase+hyphens, max 64
description: When Claude should use this skill  # truncated at 1536 chars; front-load the trigger case
when_to_use: Additional trigger phrases
argument-hint: "[issue-number]"
arguments: [issue, branch]
disable-model-invocation: false        # true = user-only (not auto-triggered)
user-invocable: true                   # false = Claude-only
allowed-tools: Bash(git *) Read Grep
model: inherit
effort: medium
context: fork                          # run in a fork subagent
agent: Explore
paths: ["src/api/**/*.ts"]
hooks: { ... }
shell: bash
---
```

**Substitutions**: `$ARGUMENTS`, `$0..$9`, `$name`, `${CLAUDE_SKILL_DIR}`, `${CLAUDE_SESSION_ID}`.

**Bash injection**: inline form (backtick + `!` + backtick-command-backtick) or fenced block with `!` after the opening three backticks. Executes **before** the LLM sees the content. ⚠️ Write examples as prose in SKILL.md files to avoid triggering injection on load.

**When to create a skill**: procedure (a) repeats, (b) is non-trivial, (c) doesn't fit in 1–2 lines of CLAUDE.md.

Candidates: `new-feature-branch`, `prepare-pr`, `release-checklist`, domain-specific workflows.

### `.claude/commands/*.md` — legacy

Don't create new ones. Migrate existing to skills.

## `.mcp.json` — project MCP servers

Only project-specific servers here. Add commands:
```bash
claude mcp add --transport http <name> <url>
claude mcp add --transport stdio --env KEY=VAL <name> -- npx -y <package>
```
First time — approval dialog; list explicitly in `enabledMcpjsonServers`.

## `.claude/settings.json` template

Hierarchy (higher = wins): managed → CLI → `.claude/settings.local.json` (gitignored) → `.claude/settings.json` (project) → `~/.claude/settings.json`. Arrays **merge**.

```json
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "permissions": {
    "allow": [
      "Bash(make *)",
      "Bash(git status)", "Bash(git diff:*)", "Bash(git log:*)",
      "Read", "Grep", "Glob"
    ],
    "ask":  ["Bash(git push *)"],
    "deny": [
      "Bash(rm -rf *)",
      "Bash(git push --force*)",
      "Read(./.env)", "Read(./.env.*)", "Read(./secrets/**)"
    ],
    "defaultMode": "default"
  },
  "enableAllProjectMcpServers": false,
  "enabledMcpjsonServers": []
}
```

Eval order: **deny → ask → allow** (first match wins). `Bash(make *)` — highest priority.

`settings.local.json` — **must be in `.gitignore`**.

## Makefile skeleton

If absent — create. If incomplete — extend. All agents/skills/commands use only `make` targets.

```makefile
SHELL = /bin/bash
### https://makefiletutorial.com/

.PHONY: help create-local-files up down restart logs ps shell test lint fix migrate seed deploy clean
.DEFAULT_GOAL := help

##@ Help
help:  ## Display this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z0-9_-@]+:.*?##/ { printf "  \033[36m%-25s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Init
create-local-files: ## Init local config (.env.local etc.)

##@ Docker
up:        ## Docker UP
down:      ## Docker DOWN
restart:   ## Docker restart
logs:      ## Tail logs
ps:        ## Status
shell:     ## Shell into main container

##@ Dev
test:      ## Tests
lint:      ## Linters
fix:       ## Auto-fix

##@ DB
migrate:   ## Migrations
seed:      ## Seed

##@ Release
deploy:    ## Deploy
clean:     ## Clean caches/artifacts
```

Requirements:
- `##@ Section` groups, `## description` on every target
- `.PHONY` for non-file targets, `.DEFAULT_GOAL := help`
- Params via `include .env` + `export`, not hardcoded
- `CLAUDE.md` must say: "if a needed operation is missing — add a target, then use it"

## Hooks reference

### Events

`SessionStart` · `SessionEnd` · `UserPromptSubmit` · `UserPromptExpansion` · `PreToolUse` · `PostToolUse` · `PostToolUseFailure` · `PostToolBatch` · `PermissionRequest` · `PermissionDenied` · `Notification` · `SubagentStart` · `SubagentStop` · `TaskCreated` · `TaskCompleted` · `Stop` · `StopFailure` · `TeammateIdle` · `InstructionsLoaded` · `ConfigChange` · `CwdChanged` · `FileChanged` · `WorktreeCreate` · `WorktreeRemove` · `PreCompact` · `PostCompact` · `Elicitation` · `ElicitationResult`

### Handler types

`command` · `http` · `mcp_tool` · `prompt` · `agent`

Fields: `matcher`, `if`, `timeout`, `async`, `asyncRewake`, `shell`, `once`, `statusMessage`

### Exit codes (command handler)

| Code | Meaning |
|---|---|
| `0` | OK; stdout JSON parsed and injected |
| `2` | Blocking; stderr message sent to Claude |
| other | Non-blocking |

`WorktreeCreate` blocks on any non-zero exit.

### Matcher syntax

- `*` or empty — all tool calls
- Letters + digits + `_` + `|` — exact name or OR list
- Any other chars — treated as JS regex

### Security rules

- Hooks from project-settings are git-shared → **never put credentials in them**
- Use `$CLAUDE_PROJECT_DIR` for paths
- Validate `tool_input` via `jq`
- HTTP hooks: only `allowedEnvVars` are interpolated

## Token economy principles

1. **CLAUDE.md hierarchy** — common in `~/.claude/CLAUDE.md`, specifics in `./CLAUDE.md`. Don't duplicate.
2. **Import, not copy** — `@path/to/file.md` (max 5 hops; doesn't shrink context, but easier to maintain).
3. **`.claude/rules/` with `paths:`** — load only on match.
4. **Narrow sub-agents** — keeps main context leaner.
5. **Skills with `disable-model-invocation: true`** — description not resident in context.
6. **Limits**: `CLAUDE.md` ≤ 200 lines, `SKILL.md` ≤ 500 lines, `description+when_to_use` ≤ 1536 chars.
7. **Lazy loading** — skill supporting files load on demand (only when the body links and the model follows).
8. **Reference style** — "routes in `X`, read when needed."
9. **Explicit no-read zones** in CLAUDE.md.
10. **Single entry point — `Makefile`** — agents don't reproduce recipes.
11. **HTML comments** in CLAUDE.md for maintainer notes without token cost.
12. **Auto memory** (v2.1.59+) — built-in; don't duplicate in CLAUDE.md.

## Security and git checklist

- `.gitignore`: `CLAUDE.local.md`, `.claude/settings.local.json`, secrets (`.env*`, `*credentials*`)
- First `@import` of external files / `.mcp.json` — triggers Claude Code approval dialog
- All deliverables in one commit using project's `git log` style, **only when user explicitly asks to commit**
