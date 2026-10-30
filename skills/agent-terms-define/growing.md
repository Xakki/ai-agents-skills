# Growing the abbreviations dictionary

Two-tier model + add flow + promotion. Opened from `SKILL.md` only when you're
actually adding or promoting an abbreviation.

## Two-tier model

- **Canonical — `dictionary.tsv`** in this plugin's git repo. The single source
  of truth: shared, committed, reviewed. Format: `abbr<TAB>full`, 2 cols, real
  tab delimiter, one row per abbr.
- **Capture buffer — a LOCAL file** outside the plugin at
  `${ABBR_LOCAL:-$HOME/.config/abbr/local.tsv}` (env `ABBR_LOCAL` overrides, else
  that default). Same `abbr<TAB>full` TSV. Personal staging only, NOT a source of
  truth. Lines starting with `#` are comments (ignored when reading).

Both files are auto-injected into every session by the `SessionStart` hook
(`hooks/abbr-inject.sh`), so anything you append to the buffer is in context from
the next session on.

## Add flow (mid-work, instant)

Encountered or coined a genuinely mainstream abbr absent from both files → append
one `abbr<TAB>full` row to the capture buffer:

```sh
f="${ABBR_LOCAL:-$HOME/.config/abbr/local.tsv}"; mkdir -p "$(dirname "$f")"
printf '%s\t%s\n' "abbr" "full form" >> "$f"
```

No plugin commit needed. Dubious / local / stack- or company-specific → spell the
word out in full, do NOT add it anywhere.

## Promotion (periodic, separate step)

Review the capture buffer, then:

1. Move genuinely mainstream rows into the plugin `dictionary.tsv` (this then
   needs commit + push from the checkout).
2. Delete promoted rows from the buffer.
3. Drop buffer rows that were dubious/local or already in canonical.
