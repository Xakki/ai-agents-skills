# ai-agents-skills installed

The Hermes plugin is installed. Its shared skills are read-only, namespaced
plugin skills and appear in slash-command autocomplete. Start a new Hermes
session (or run `/reload-skills`) and type `/` then Tab. Use `/ai-kanban` for
the plugin's kanban workflow because `/kanban` is a built-in Hermes command.

Load a workflow explicitly:

```text
skill_view("ai-agents-skills:qa-check")
skill_view("ai-agents-skills:git-flow")
```

The prompts from `agents/` are exposed as skills too:

```text
skill_view("ai-agents-skills:agent-log-investigator")
skill_view("ai-agents-skills:agent-db-schema")
```

Check plugin state with:

```bash
hermes plugins list --plain --no-bundled
```

Telegram hooks are optional and remain no-ops until `tg-notify` is configured.
Hermes has no permission/idle plugin event, so only prompt-start, task-finished,
and stale-notification cancellation hooks are mapped.

See the "Install (Hermes)" section in `README.md` for compatibility notes.
