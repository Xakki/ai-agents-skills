# ai-agents-skills installed

The Hermes plugin is installed. Its shared skills are read-only, namespaced
plugin skills and can be loaded by their namespace. Start a new Hermes session
(or run `/reload-skills`) and call `skill_view("ai-agents-skills:kanban")` for
the plugin's Kanban workflow or `skill_view("ai-agents-skills:knbn")` for its
portable alias. The built-in `/kanban` board command remains separate.

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
