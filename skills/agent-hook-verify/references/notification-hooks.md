# Notification lifecycle hooks

Treat manual notifications and agent lifecycle hooks as separate mechanisms.
Enabling a hook does not authorize an extra manual notification. Check the
active runtime, event mapping, destination binding and the installed plugin's
current configuration without printing secrets.

The optional Telegram hooks use `TG_NOTIFY_ENABLED`,
`TG_NOTIFY_PERM_THRESHOLD`, `TG_NOTIFY_IDLE_THRESHOLD`, `TG_NOTIFY_DELAY`,
`TG_NOTIFY_DEBOUNCE`, `TG_NOTIFY_STOP_THRESHOLD`, `TG_NOTIFY_STOP_DELAY` and
`TG_NOTIFY_STOP_DEBOUNCE`. Inspect installed defaults instead of assuming them.
Disabling new notifications does not cancel pending work. Distinguish
configuration, isolated execution and actual delivery; a real send needs
separate authorization.
