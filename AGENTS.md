# AGENTS.md

This repository ships **three** plugins from the same source tree: a Claude
Code plugin, a Codex plugin, and a Cursor Agent CLI/IDE plugin:

- `.claude-plugin/plugin.json` + `.claude-plugin/marketplace.json` — Claude
  Code manifest and marketplace entry.
- `.codex-plugin/plugin.json` — Codex plugin manifest.
- `.cursor-plugin/plugin.json` + `.cursor-plugin/marketplace.json` — Cursor
  Agent CLI/IDE manifest and marketplace entry.

## Conventions

- Shared skills live under `skills/` and are used by **all three**
  integrations — don't fork or duplicate a skill per runtime.
- Runtime-specific lifecycle hook maps stay separate: `hooks/hooks.json`
  (Claude Code), `hooks/codex-hooks.json` (Codex), and
  `hooks/cursor-hooks.json` (Cursor — routes every event through
  `hooks/cursor-adapter.sh`, which normalizes Cursor's payload field names
  into the shape the shared `tg-*.sh`/`abbr-inject.sh` scripts already
  expect). Do not merge them, and put any Cursor-specific translation logic
  in the adapter, not in the shared scripts. Cursor has no
  `Notification`/`PermissionRequest` equivalent — the "needs attention" ping
  is intentionally not wired for Cursor; see
  [docs/superpowers/specs/2026-07-31-cursor-plugin-design.md](docs/superpowers/specs/2026-07-31-cursor-plugin-design.md).
- When changing shared behavior (a skill, an agent, a hook script), preserve
  **all three** integrations — verify the change still works for Claude
  Code, Codex, and Cursor, and update every manifest the change affects
  metadata for (e.g. `version`).
- All authored repository text (skills, docs, manifests, commit messages)
  is English.
- See `README.md` for install/enable/verify steps for each runtime.
