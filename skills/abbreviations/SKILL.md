---
name: abbreviations
description: Authoritative, ever-growing dictionary of standard developer abbreviations for naming (variables, functions, classes, CSS classes, tokens) and for terse technical writing — the single source of truth new abbreviations get appended to, never duplicated elsewhere. Consult it before shortening any identifier; only widely-recognized, at-a-glance abbreviations are allowed, never invented/private ones. Триггеры RU: «сокращение», «сокращения», «словарь сокращений», «как назвать переменную/функцию коротко», «пополни словарь», «добавь сокращение», «общепринятое сокращение», «сократи имя». EN: «abbreviation», «abbreviations», «short name», «naming convention», «shorten», «add to the abbreviations dictionary», «glossary», «acronym».
---

# abbreviations — dictionary for naming

Single source of truth for standard abbreviations used in names (vars / fns /
classes / CSS classes / tokens) and in terse technical text. Growing list —
never duplicate it elsewhere (a project `CLAUDE.md` keeps only policy + a
compact core + a pointer here).

## Policy

- **Only mainstream, at-a-glance abbrs.** Use abbrs any dev recognizes on
  sight. No private / project / company jargon in the canonical dict — it is
  shared across all projects. No personal data (shared plugin).
- **Names self-explain.** A var / fn / class / CSS class / token must be clear
  from its name alone; if you have to comment what a name means, rename it.
- **Comments explain "why", not "what".** A good name needs no "what" note.

## Two-tier model

- **Canonical — `dictionary.tsv`** in this plugin git repo. The single source
  of truth: shared, committed, reviewed. Format: `abbr<TAB>full`, 2 cols,
  real tab delimiter, one row per abbr.
- **Capture buffer — a LOCAL file** outside the plugin at
  `${ABBR_LOCAL:-$HOME/.config/abbr/local.tsv}` (env `ABBR_LOCAL` overrides,
  else that default). Same `abbr<TAB>full` TSV format. Personal staging only,
  NOT a source of truth. Auto-create on first append
  (`mkdir -p "$(dirname …)"`). Lines starting with `#` are comments; ignore
  them when reading.

## Consult flow

Naming a var / fn / class / CSS class / token, or writing terse text (comment,
commit msg, log) → read BOTH `dictionary.tsv` and the buffer (if it exists). A
hit in either → use it as-is (form/case from the file). Miss → see Add flow.

## Add flow (mid-work, instant)

Encountered or coined a genuinely mainstream abbr absent from both files →
append one `abbr<TAB>full` row to the capture buffer:

```sh
f="${ABBR_LOCAL:-$HOME/.config/abbr/local.tsv}"; mkdir -p "$(dirname "$f")"
printf '%s\t%s\n' "abbr" "full form" >> "$f"
```

No plugin commit needed. Dubious / local / stack- or company-specific → spell
the word out in full, do NOT add it anywhere.

## Promotion (periodic, separate step)

Review the capture buffer, then:
1. Move genuinely mainstream rows into the plugin `dictionary.tsv` (this then
   needs commit + push from the checkout).
2. Delete promoted rows from the buffer.
3. Drop buffer rows that were dubious/local or already in canonical.

## Disambiguation

The data file stays clean 2-col, so ambiguous abbrs are resolved here. When an
abbr below is ambiguous in context, pick the longer explicit name or a
qualifying prefix per the note — don't guess.

- `acc` — accumulator (in a loop/reduce) vs account (auth/billing code). On
  any risk of confusion, spell the full word.
- `res` — response vs resource. If a module already uses `res`=resource, use
  `resp` for response.
- `tx` — transaction (DB/backend, the default) vs transmit/text (radio/net
  code). In network/radio code, use an explicit name.
- `mux` — mutex vs multiplexer (HTTP router). Qualify by context.
- `ns` — namespace vs nanosecond. Pick the explicit name.
- `num` — number, not identifier — don't confuse with `id`.
- `ref` — a logical reference/key, NOT a pointer; use `ptr` for pointers.

## Full dictionary

See [dictionary.tsv](dictionary.tsv) — the full, ever-growing list, kept in a
separate TSV so this SKILL.md stays compact and the list can grow freely.
