<!-- Adapted from agent-plugin-lifecycle-audit, CC BY 4.0; source did not identify an author. -->

# Read-only plugin and hook evidence map

## Minimum evidence table

| Claim | Preferred evidence | Safe interpretation |
|---|---|---|
| Active home | environment lookup plus runtime state | Do not assume `~/.hermes` when a profile override exists |
| Plugin enabled | runtime plugin introspection + config | Enabled means eligible to load, not that every capability is active |
| Hook declared | manifest/config with `path:line` | Declaration only |
| Hook registered | runtime hook/plugin listing or startup registration path | Distinguish Python callbacks from compatibility shell manifests |
| Hook reachable | callback → script/API call graph | Include current settings and event prerequisites |
| Hook observed | sanitized log/state counts | Historical corroboration only |
| Delivery possible | non-secret credential presence + sender code path | Do not read or print secrets to establish this |

## Hermes-specific checks

- `hermes plugins list` establishes plugin enablement and source metadata.
- `hermes hooks list` reports declarative shell hooks configured in Hermes; an
  empty result does not rule out Python plugin lifecycle hooks.
- Inspect `plugin.yaml` for `provides_hooks`, then the plugin `register()` body.
- Trace each callback to its fixed script and record whether the script is
  actually called by the current host runtime.
- A Claude/Cursor `hooks.json` is a compatibility artifact unless the current
  host explicitly loads that schema.
- For delayed notifications, map start marker, duration threshold, debounce,
  pending payload, cancellation marker, delay, sender invocation, and delivery
  log separately.

## Safe command set

```bash
hermes plugins list
hermes hooks list
python3 -m py_compile path/to/plugin.py
bash -n path/to/hook.sh
```

Use `stat`, file existence checks, and filtered counters for mutable state. Do
not invoke sender scripts, synthetic hook payloads, or external API paths when
the audit is read-only.

## Reporting language

Prefer precise labels: `declared`, `registered`, `reachable`, `observed`,
`currently configured`, and `not established`. State when a credential file was
intentionally not opened. Cite source as `path:line`; list commands separately
from conclusions.
