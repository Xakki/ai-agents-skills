---
name: abbreviations
description: >
  Authoritative dictionary of standard developer abbreviations for variables,
  functions, classes, CSS classes, tokens, and terse technical writing. Use it
  before shortening a name, choosing a naming convention, or adding to the
  shared abbreviation dictionary, glossary, or acronym list. Accept only
  widely recognized terms.
---

# abbreviations — naming & terse-writing dictionary

Single source of truth for standard abbreviations in names (vars / fns / classes
/ CSS classes / tokens) and terse text (comments, commit msgs, logs).

This policy, the canonical `dictionary.tsv`, **and** your local capture buffer
`${ABBR_LOCAL:-$HOME/.config/abbr/local.tsv}` (if it exists) are **auto-injected
into every session** — incl. subagents — by this plugin's `SessionStart` hook
(`hooks/abbr-inject.sh`). All of it is already in your context; you don't open
the files to look an abbr up. Never duplicate the dict anywhere else.

## Policy

- **Only mainstream, at-a-glance abbrs.** Ones any dev recognizes on sight. No
  private / project / company jargon in the canonical dict (shared across all
  projects, no personal data). Dubious / local / stack-specific → spell the word
  out in full, don't add it.
- **Names self-explain.** A var / fn / class / CSS class / token must be clear
  from its name alone; if you must comment what a name means, rename it.
- **Comments explain "why", not "what".** Minimal comments — only a nontrivial
  edge case, a bug workaround, a hidden invariant. A good name needs no "what".

## Disambiguation

The 2-col data file can't resolve ambiguity — pick the explicit form, don't guess:

- `res` — if a module already uses `res`=resource, use `resp` for response.
- `acc` — accumulator vs account: on any risk of confusion, spell it out.
- `tx` — transaction (the default); in net/radio code spell out transmit/text.
- `mux` — mutex vs multiplexer (HTTP router): qualify by context.
- `ns` — namespace vs nanosecond: pick the explicit name.
- `ref` vs `ptr` — `ref` = logical reference/key, `ptr` = pointer.

## Growing the dictionary

Coined or hit a genuinely mainstream abbr missing from both files → append it to
the capture buffer, and periodically promote buffer rows into canonical. Full
flow (buffer format, append snippet, promotion steps) → [growing.md](growing.md).
