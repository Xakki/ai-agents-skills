---
name: tg-notify-timers
description: View or change the timers/thresholds that control the tg-notify hooks (Stop + Notification) — idle/permission/stop thresholds, delivery delays, debounce. They are environment variables that override the hooks' built-in defaults; this skill sets them in settings.json. Use when the user asks to tune Telegram notification delays, debounce, idle/permission/stop thresholds, or to silence/sensitize TG notifications. Triggers (RU/EN) — «таймеры тг», «пороги тг», «debounce TG», «idle threshold», «когда писать в телеграм», «увеличить/уменьшить пороги уведомлений», «tune tg notify», «adjust telegram thresholds».
---

# tg-notify-timers — TG-hook timers config

Manages the 7 vars the plugin hooks `tg-on-notification.sh` and `tg-on-stop.sh`
use to decide when and after what delay to send a message to Telegram.

## How it works (important)

The hooks read each value as `${TG_NOTIFY_*:-<default>}` — i.e. they **take the number
from the env, and if the var is absent — the built-in default**. The hook scripts live in
the read-only plugin cache (`~/.claude/plugins/cache/...`), you **can't** edit them —
they get overwritten on update. So the only way to change a timer is to
**set an env var** that overrides the default.

Canonically — in the `env` of `~/.claude/settings.json` (the hooks inherit its environment).
**The "default" profile = none of the 7 vars set** → the built-in
defaults apply. Changes are picked up **after a restart** of Claude Code (env is read at startup).

## Params

| Var | Hook | Semantics | Default    |
|---|---|---|------------|
| `TG_NOTIFY_PERM_THRESHOLD` | notification | min duration (sec) for "🔐 Требуется разрешение" | 1200 (20m) |
| `TG_NOTIFY_IDLE_THRESHOLD` | notification | min duration (sec) for "⏰ Ожидает ввода" | 1200 (20m) |
| `TG_NOTIFY_DELAY` | notification | delivery delay (cancel window, sec) | 1800 (30m) |
| `TG_NOTIFY_DEBOUNCE` | notification | min interval between schedules per session | 300 (5m)   |
| `TG_NOTIFY_STOP_THRESHOLD` | stop | min task duration for a Stop notification | 1200 (20m) |
| `TG_NOTIFY_STOP_DELAY` | stop | Stop delivery delay (cancel window) | 1800 (30m) |
| `TG_NOTIFY_STOP_DEBOUNCE` | stop | min interval between Stop schedules per session | 1200 (20m) |

All values are seconds, stored in JSON as strings (`"1800"`).

## View current

```bash
jq '.env | with_entries(select(.key | startswith("TG_NOTIFY_")))' ~/.claude/settings.json
```
Empty → the defaults from the table apply.

## Change

Edit `env` in `~/.claude/settings.json` (directly via Edit / skill `update-config`,
or the jq below). One timer:

```bash
jq '.env.TG_NOTIFY_STOP_THRESHOLD = "1800"' ~/.claude/settings.json > /tmp/s.json && mv /tmp/s.json ~/.claude/settings.json
```

Reset to default (remove all 7 → built-in defaults):

```bash
jq 'del(.env.TG_NOTIFY_PERM_THRESHOLD, .env.TG_NOTIFY_IDLE_THRESHOLD, .env.TG_NOTIFY_DELAY, .env.TG_NOTIFY_DEBOUNCE, .env.TG_NOTIFY_STOP_THRESHOLD, .env.TG_NOTIFY_STOP_DELAY, .env.TG_NOTIFY_STOP_DEBOUNCE)' ~/.claude/settings.json > /tmp/s.json && mv /tmp/s.json ~/.claude/settings.json
```

After any change — restart Claude Code so the hooks see the new env.

## Profiles

Apply with a single jq merge into `.env`.

### quieter
```bash
jq '.env += {TG_NOTIFY_PERM_THRESHOLD:"1800",TG_NOTIFY_IDLE_THRESHOLD:"1200",TG_NOTIFY_DELAY:"600",TG_NOTIFY_DEBOUNCE:"600",TG_NOTIFY_STOP_THRESHOLD:"1800",TG_NOTIFY_STOP_DELAY:"900",TG_NOTIFY_STOP_DEBOUNCE:"600"}' ~/.claude/settings.json > /tmp/s.json && mv /tmp/s.json ~/.claude/settings.json
```

### more sensitive
```bash
jq '.env += {TG_NOTIFY_PERM_THRESHOLD:"600",TG_NOTIFY_IDLE_THRESHOLD:"300",TG_NOTIFY_DELAY:"180",TG_NOTIFY_DEBOUNCE:"180",TG_NOTIFY_STOP_THRESHOLD:"600",TG_NOTIFY_STOP_DELAY:"300",TG_NOTIFY_STOP_DEBOUNCE:"180"}' ~/.claude/settings.json > /tmp/s.json && mv /tmp/s.json ~/.claude/settings.json
```

### disable (thresholds set unreachable)
```bash
jq '.env += {TG_NOTIFY_PERM_THRESHOLD:"99999999",TG_NOTIFY_IDLE_THRESHOLD:"99999999",TG_NOTIFY_STOP_THRESHOLD:"99999999"}' ~/.claude/settings.json > /tmp/s.json && mv /tmp/s.json ~/.claude/settings.json
```

## Verification

```bash
# what is set in the environment
jq '.env | with_entries(select(.key | startswith("TG_NOTIFY_")))' ~/.claude/settings.json
# JSON valid?
jq empty ~/.claude/settings.json && echo "settings.json OK"
# log: what the hook schedules/sends (runtime home: $TG_NOTIFY_HOME, defaults to ~/.local/state/tg-notify)
tail -50 "${TG_NOTIFY_HOME:-$HOME/.local/state/tg-notify}/tg-notify.log" 2>/dev/null
# active pending payload files
ls -la "${TG_NOTIFY_HOME:-$HOME/.local/state/tg-notify}/pending/"*/ 2>/dev/null
```

## Related

- Plugin hooks (read-only, **do not edit**): `hooks/tg-on-notification.sh`, `hooks/tg-on-stop.sh`,
  `hooks/tg-prompt-start.sh`, `hooks/tg-cancel-pending.sh`.
- Sending and creds/targeting — skill `tg-notify` (`skills/tg-notify/`).
