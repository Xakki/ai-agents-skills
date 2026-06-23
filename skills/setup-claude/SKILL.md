---
name: setup-claude
description: Universal template to set up Claude Code in any repository — generates CLAUDE.md, sub-agents, skills, .mcp.json, settings.json, and Makefile. Use when initializing Claude Code in a new project, auditing existing config, or migrating .claude/commands/ to skills. Token-economy focused; mandates make-targets; always asks user which hooks to enable.
when_to_use: User says "настрой Claude Code", "init claude", "сделай CLAUDE.md", "проанализируй проект и настрой агентов", "/setup-claude", or asks to configure sub-agents/skills/MCP/hooks for a repo.
disable-model-invocation: true
allowed-tools: Read Glob Grep Bash WebFetch WebSearch Write Edit
---

# Setup Claude Code in this repository

Универсальный шаблон, не зависит от стека. Все артефакты — локально в репо и под git.

## 1. Sources (обязательно — WebFetch перед работой)

Canonical domain: `code.claude.com/docs/en/*`. Full URL list with per-page descriptions → [reference.md](reference.md).

If 404 → `WebSearch site:code.claude.com <topic>`. Ignore third-party blogs.

## 2. Discovery — Phase 1 (no file writes)

1. `git log --oneline -30`, active branches, manifests (`package.json`, `composer.json`, `go.mod`, `Makefile`, `docker-compose.yml`)
2. Existing `CLAUDE.md` (managed → user → project), `.claude/rules/`, `.claude/agents/`, `.claude/skills/`, `.claude/commands/`, `.mcp.json`, `AGENTS.md`
3. README/CONTRIBUTING/TODO — extract **team process** and **no-touch zones** only
4. Stack map, monolith vs modules, legacy vs new; Makefile quality
5. Skip: `vendor/`, `node_modules/`, `*_data/`, `dist/`, `build/`, binaries

Report ≤ 30 lines: stacks, existing Claude config, proposed agents/skills/MCP/rules, Makefile plan, hook options (§4 below). **Wait for ok.** Alternative: suggest `/init` as starting point, then refine.

## 3. Deliverables — Phase 2 (after confirmation)

| Artifact | Key constraint |
|---|---|
| `CLAUDE.md` | ≤ 200 lines; only what can't be read from code; mandate `make <target>` for all ops |
| `.claude/rules/*.md` | Optional; use `paths:` frontmatter to scope to subtrees |
| `.claude/agents/*.md` | `name` + `description` required; explicit `tools:`; narrow scope |
| `.claude/skills/<name>/SKILL.md` | ≤ 500 lines; happy-path only; bulk detail → neighbor files |
| `.mcp.json` | Project-specific only; list in `enabledMcpjsonServers`; use `claude mcp add` |
| `.claude/settings.json` | Commit; `settings.local.json` → `.gitignore`; deny→ask→allow (first match) |
| `Makefile` | Required; create if absent; `make help` with `##@` groups; all ops via make |

Full frontmatter fields, settings.json template, and Makefile skeleton → [reference.md](reference.md).

## 4. Hooks — mandatory user ask

⚠️ **Never add hooks without explicit user consent.** After discovery, present:

```
[ ] PreToolUse + Bash: block rm -rf, git push --force, direct docker/npm bypassing make — low risk
[ ] PreToolUse + Edit|Write: block writes to .env*, vendor/, DB dumps — low risk
[ ] PostToolUse + Edit|Write: make lint after edits — medium risk (modifies code)
[ ] UserPromptSubmit: inject git status --short — low risk, +tokens
[ ] Stop / SubagentStop: Telegram/Slack notification for long tasks — low risk
[ ] SessionStart: inject make help — medium risk (+tokens)
[ ] InstructionsLoaded: log which CLAUDE.md/rules loaded — zero risk
Enable: <numbers> / none
```

Security: hooks in project-settings are git-shared → no credentials; use `$CLAUDE_PROJECT_DIR`; validate `tool_input` via `jq`. Full event list, handler types, exit codes → [reference.md](reference.md). **Default: no hooks.**

## 5. Definition of Done

- [ ] All frontmatter fields valid per official docs
- [ ] `CLAUDE.md` ≤ 200 lines; doesn't duplicate parent
- [ ] Agents: `name` + `description` mandatory; `tools:` explicit
- [ ] Skills: `.claude/skills/<name>/SKILL.md`; no new `.claude/commands/`
- [ ] `settings.json` committed; `settings.local.json` + `CLAUDE.local.md` in `.gitignore`
- [ ] `Makefile` exists; `make help` works with sections
- [ ] `CLAUDE.md` mandates `make <target>` for all operations
- [ ] Hooks agreed with user
- [ ] Test run: typical question ≤ 5 tool calls
- [ ] No reads of `vendor/`, `node_modules/`, DB dumps during setup
- [ ] Final report: files list, line counts, make targets added, hooks enabled

## 6. What NOT to do

- No "universal" agents — use `Explore`, `Plan`, `general-purpose`
- No README/docs copied into `CLAUDE.md`
- No MCP/skills/agents added "just in case"
- No hooks without explicit user ok
- No direct stack commands when a `make` target exists or can be added
- No new `.claude/commands/*.md` — use skills
- No `docs/architecture.md` created just for documentation
- No changes to project code (only Claude Code config + Makefile)
