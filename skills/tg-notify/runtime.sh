#!/usr/bin/env bash
# Shared runtime paths for tg-notify (sender + hooks). Source me, don't run me.
#
# Credentials and mutable state live OUTSIDE the plugin directory (the plugin
# dir is read-only in the install cache). State home resolution:
#   $TG_NOTIFY_HOME  → explicit override
#   $CLAUDE_PLUGIN_DATA → per-plugin writable dir (set by Claude Code)
#   $XDG_STATE_HOME/tg-notify  → else $HOME/.local/state/tg-notify

TG_SKILL_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

TG_NOTIFY_HOME="${TG_NOTIFY_HOME:-${CLAUDE_PLUGIN_DATA:-${XDG_STATE_HOME:-$HOME/.local/state}/tg-notify}}"
TG_STATE_DIR="$TG_NOTIFY_HOME/state"
TG_PENDING_DIR="$TG_NOTIFY_HOME/pending"
TG_LOG_FILE="$TG_NOTIFY_HOME/tg-notify.log"
TG_FAILED_DIR="$TG_NOTIFY_HOME/failed"

TG_SENDER="$TG_SKILL_DIR/tg-notify.sh"

# Credentials file (chmod 600). NOT shipped with the plugin — create from
# .env.example. Real environment variables override whatever it sets.
TG_ENV_FILE="${TG_NOTIFY_ENV:-${XDG_CONFIG_HOME:-$HOME/.config}/tg-notify/.env}"
