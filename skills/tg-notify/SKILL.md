---
name: tg-notify
description: Send a Telegram notification with a short report (DM / group / channel, configurable). Auto-trigger ONLY when a just-finished task took >20 min of wall-clock time (deploy, rsync/backup, big build, batch/scheduled job) — the user has likely left the terminal. Bypass the threshold only when the user explicitly asks ("send to telegram", "notify in TG", "ping me when done") or when invoked from a scheduled / background job. MAIN THREAD ONLY — subagents / teammates do NOT use this skill; they return their report to the teamlead, who decides whether to notify.
---

# tg-notify

Manual sender of a Telegram message to a configurable destination (DM, group, or channel) via a bot.
The plugin also ships **hooks** (`../../hooks/`) that auto-notify on long turns and permission/idle
prompts — those fire on their own once configured; this skill is the **manual** sender.

## When to use

**Threshold: 20-minute minimum for auto-sends** (matches the `TG_NOTIFY_STOP_THRESHOLD` hook default).
Shorter → just answer in the terminal. Unknown duration → treat as below threshold, don't send.

Auto-send only if one of:
- A long-running op (**>20 min**) just finished — send a short status report with timing.
- The user explicitly asks for a Telegram notification/ping (any duration).
- A scheduled / background job needs to report (any duration).

Track duration honestly with `SECONDS=0; <command>; dur=$SECONDS` so the check is real.

## Main thread only

If you are a **subagent / teammate** (spawned with a task by another agent, no direct line to the
user), do **not** invoke this skill — return your report to the teamlead and let them decide. When
in doubt, assume subagent and hand the report up. (Auto-send hooks are unaffected; they fire on the
main session's lifecycle, not from inside a subagent.)

## How to invoke

```bash
TG="${CLAUDE_PLUGIN_ROOT}/skills/tg-notify/tg-notify.sh"

# Short status (title only)
"$TG" -s ok -t "Backup завершён" -m "wephost: 64 GiB, 12m 03s"

# Title + multi-line body via stdin (preferred for reports)
{
  echo "rsync /home/wephost: 64.0 GiB, 12m 03s"
  echo "Все сервисы запущены."
} | "$TG" -s ok -t "saFin: миграция завершена"

# Send to a different destination than the default (e.g. a channel)
echo "released v1.2.3" | "$TG" -s ok -t "Deploy" -c "@my_channel"
```

## Reference

Configuration (env vars, destination types), full flag table, and conventions live in
[reference.md](reference.md) — read it when you're actually sending.
