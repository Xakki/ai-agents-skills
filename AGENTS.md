# AGENTS.md

This repository ships **both** a Claude Code plugin and a Codex plugin from
the same source tree:

- `.claude-plugin/plugin.json` + `.claude-plugin/marketplace.json` — Claude
  Code manifest and marketplace entry.
- `.codex-plugin/plugin.json` — Codex plugin manifest.

## Conventions

- Shared skills live under `skills/` and are used by **both** integrations —
  don't fork or duplicate a skill per runtime.
- Runtime-specific lifecycle hook maps stay separate: `hooks/hooks.json`
  (Claude Code) and `hooks/codex-hooks.json` (Codex). Do not merge them.
- When changing shared behavior (a skill, an agent, a hook script), preserve
  **both** integrations — verify the change still works for Claude Code and
  for Codex, and update both manifests if the change affects metadata each
  one declares (e.g. `version`).
- All authored repository text (skills, docs, manifests, commit messages)
  is English.
- See `README.md` for install/enable/verify steps for each runtime.
