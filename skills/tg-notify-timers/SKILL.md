---
name: tg-notify-timers
description: Inspect or tune Telegram hook thresholds, delivery delays and debounce; таймеры уведомлений, задержка телеграм.
---

# Telegram notification timers

The hooks read their settings from the process environment. Inspect and update them through the active agent's supported configuration interface; do not assume a particular agent, config path, or writable plugin cache. Values are seconds. Unset variables use the defaults below.

| Variable | Default | Purpose |
|---|---:|---|
| `TG_NOTIFY_PERM_THRESHOLD` | 1200 | Minimum time before a permission notification |
| `TG_NOTIFY_IDLE_THRESHOLD` | 1200 | Minimum time before an idle notification |
| `TG_NOTIFY_DELAY` | 1800 | Notification delivery delay |
| `TG_NOTIFY_DEBOUNCE` | 300 | Minimum interval between notification schedules |
| `TG_NOTIFY_STOP_THRESHOLD` | 1200 | Minimum task duration for a stop notification |
| `TG_NOTIFY_STOP_DELAY` | 1800 | Stop delivery delay |
| `TG_NOTIFY_STOP_DEBOUNCE` | 1200 | Minimum interval between stop schedules |

Set only the values requested, preserving unrelated configuration. To disable new Telegram lifecycle notifications set `TG_NOTIFY_ENABLED=0` (also accepts `false`, `no`, or `off`, case-insensitively). Re-enabling or changing the environment does not cancel notifications already scheduled by an older process; inspect and cancel pending work through the supported runtime interface when authorized.

Confirm which environment the hooks actually inherit. Some agents require a new process or session before changes take effect; verify this rather than assuming a restart policy. Inspect the runtime's notification state or logs without exposing tokens, destinations, or message contents, and report the configured values separately from an actual delivery test. Sending a notification requires authorization for the specific test and destination.
