# AGENTS.md

This repository ships **four** plugins from the same source tree: Claude Code,
Codex, Cursor Agent CLI/IDE, and Hermes Agent integrations:

- `.claude-plugin/plugin.json` + `.claude-plugin/marketplace.json` — Claude
  Code manifest and marketplace entry.
- `.codex-plugin/plugin.json` — Codex plugin manifest.
- `.cursor-plugin/plugin.json` + `.cursor-plugin/marketplace.json` — Cursor
  Agent CLI/IDE manifest and marketplace entry.
- `plugin.yaml` + `__init__.py` — Hermes manifest and Python registration
  adapter. It registers the shared skills read-only under the
  `ai-agents-skills:` namespace and maps compatible lifecycle hooks.

## Conventions

- Shared skills live under `skills/` and are used by **all four**
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
- Hermes lifecycle translation belongs in the root `__init__.py`; shared shell
  hooks continue to consume the normalized Claude-shaped JSON payload. Hermes
  has no permission/idle notification event, so that ping degrades safely just
  as it does under Cursor.
- When changing shared behavior (a skill, an agent, a hook script), preserve
  **all four** integrations — verify the change still works for Claude Code,
  Codex, Cursor, and Hermes, and update every manifest the change affects
  metadata for (e.g. `version`).
- Script-bearing skills must resolve the root through
  `AI_AGENTS_SKILLS_ROOT`, with Claude/Codex/Cursor root fallbacks. Hermes sets
  `AI_AGENTS_SKILLS_ROOT` during plugin registration.
- Run `pytest -q tests/test_hermes_plugin.py` and an isolated
  `hermes plugins install file://... --enable` smoke test for Hermes changes.
- All authored repository text (skills, docs, manifests, commit messages)
  is English.
- See `README.md` for install/enable/verify steps for each runtime.
