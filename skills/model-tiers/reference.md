# model-tiers — settings.json reference

Override `AI_MODEL_*` in the active runtime's `settings.json` `env` block. Same
three keys across Claude Code, Cursor, and Codex when the runtime supports an `env`
block.

## View current values (Claude Code)

```bash
jq '.env | {
  AI_MODEL_CHEAP,
  AI_MODEL_STANDARD,
  AI_MODEL_JUDGMENT
}' ~/.claude/settings.json
```

## Set overrides (Claude Code)

Merge into `env` without clobbering other keys:

```bash
jq '.env += {
  "AI_MODEL_CHEAP": "haiku",
  "AI_MODEL_STANDARD": "sonnet",
  "AI_MODEL_JUDGMENT": "opus"
}' ~/.claude/settings.json > ~/.claude/settings.json.tmp \
  && mv ~/.claude/settings.json.tmp ~/.claude/settings.json
```

Remove a single override (fall back to plugin defaults):

```bash
jq 'del(.env.AI_MODEL_CHEAP)' ~/.claude/settings.json > ~/.claude/settings.json.tmp \
  && mv ~/.claude/settings.json.tmp ~/.claude/settings.json
```

## Cursor / Codex

Use the same keys in:

- Cursor: `~/.cursor/settings.json` → `env`
- Codex: `~/.codex/settings.json` → `env` (when supported)

View / set with the same `jq` patterns, substituting the settings path.

## Precedence reminder

Process env from `settings.json` wins over `skills/model-tiers/defaults.env`.
SessionStart hook `hooks/model-tiers-inject.sh` resolves and injects the final
slugs into every session's context.
