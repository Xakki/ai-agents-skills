# Claude model-tier configuration

Use this reference only when the active runtime is Claude Code and its supported model selectors and configuration mechanism have been verified. The plugin's `defaults.env` contains Claude-family aliases; they are not defaults for Codex, Cursor, Hermes or Prime.

Explicit `AI_MODEL_CHEAP`, `AI_MODEL_STANDARD` and `AI_MODEL_JUDGMENT` environment values override the Claude defaults in the hook. Set only values authorized and supported by the active runtime, preserve unrelated settings, and confirm what a newly started session actually receives. Do not assume that other agents share Claude's configuration file or accept these aliases.
