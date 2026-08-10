---
name: model-tiers
description: >
  Map cheap, standard, and judgment work to resolved model slugs via
  AI_MODEL_*. Use to select a subagent tier, override defaults, or map
  mechanical, product-logic, and architecture work to models such as Haiku,
  Sonnet, and Opus.
---

# model-tiers — cheap / standard / judgment

Three cognitive tiers — skills and delegation rules name **tiers only**, never vendor
model slugs. Resolved slugs for this session are injected at **SessionStart**
(`hooks/model-tiers-inject.sh`) and appear in context as `cheap`, `standard`,
`judgment`.

## Tiers

| Tier | Role | Default slug |
|------|------|--------------|
| **cheap** | Mechanical, spec-complete, single-pass work (grep, rename, format, inventory) | `haiku` |
| **standard** | Routine product logic, known patterns, doc/skill edits, code review | `sonnet` |
| **judgment** | Architecture, tricky debug, cross-file synthesis, multi-source research | `opus` |

When torn between two tiers, pick the cheaper one; escalate on ambiguity. Floor =
**standard** for anything touching product logic.

## Env keys

| Key | Tier |
|-----|------|
| `AI_MODEL_CHEAP` | cheap |
| `AI_MODEL_STANDARD` | standard |
| `AI_MODEL_JUDGMENT` | judgment |

## Precedence

1. **Runtime `settings.json` env** — `{.claude\|.cursor\|.codex}/settings.json` → `env` block (process env at session start).
2. **Plugin defaults** — `skills/model-tiers/defaults.env` (shipped with the plugin).

Unset override keys fall back to defaults. **Never invent a model** — always use
the resolved slug from the map above or from SessionStart injection.

## SessionStart inject

Every session receives a tiny block:

```
## Model tiers (resolved for this session)
cheap = <slug>
standard = <slug>
judgment = <slug>
```

Pass these slugs as `model:` on every `Agent` / `Task` call. Omitting `model:` inherits
the caller's tier (expensive default).

## Configure overrides

Set `AI_MODEL_*` in the active runtime's `settings.json` `env` block. Long jq
examples → [reference.md](reference.md).

## Agent frontmatter limitation

YAML `model:` in `.claude/agents/*.md` is **not** env-expanded — frontmatter tracks
plugin defaults at authoring time. Callers must pass the **resolved slug** from the
tier map when invoking agents; skills reference tiers (`cheap`, `standard`,
`judgment`) only.
