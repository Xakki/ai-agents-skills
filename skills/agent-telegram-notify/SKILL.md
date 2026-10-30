---
name: agent-telegram-notify
description: 'Send an authorized Telegram notification or task/completion report to a configured chat or topic, and tune the notification hook timers. Use only on explicit request or authorized workflows. RU: уведомление в Telegram, отчёт в телеграм, таймеры уведомлений.'
disable-model-invocation: true
---

# Telegram notifications and reports

Manual sender of a Telegram message to a configurable destination (DM, group, channel or forum topic) via a bot. The plugin also ships optional lifecycle hooks for long turns and permission/idle prompts; this skill is the **manual** sender. Configure and enable hooks only when authorized; hook installation alone does not authorize a message.

## When to send

Send only when the user explicitly requests it or an authorized scheduled or background workflow covers the destination and message. A long task alone does not grant permission. Automatic completion notifications use the configured threshold (default 20 minutes; an unknown duration does not satisfy it); an explicit user request does not wait for the threshold. Track duration honestly with `SECONDS=0; <command>; dur=$SECONDS`.

**Main thread only.** A subagent or teammate must not invoke this skill: return the report to the lead and let them decide. When in doubt assume subagent. Auto-send hooks are unaffected; they fire on the main session's lifecycle.

## Sending

Obtain the resolved `SKILL_DIR` and the authorized destination through the runtime. Use stdin for the body so it is not passed in argv, and keep secrets out of titles and other arguments:

```bash
printf '%s\n' 'Deployment completed.' | "$SKILL_DIR/agent-telegram-notify.sh" -s ok -t 'Deployment'
```

Configuration (env vars, destination types), the flag table and conventions are in [reference.md](reference.md); read it when actually sending.

## Reports

For a task or completion report use the same sender. Resolve `TELEGRAM_NOTIFY_CHAT_ID` and the requested topic (`TELEGRAM_NOTIFY_TASK_THREAD` for task reports, `TELEGRAM_NOTIFY_COMPLETION_THREAD` for completion reports) from the configured environment or credential interface. If routing is ambiguous or a required destination or topic is absent, obtain it before sending; never silently fall back to another chat or topic. Do not assume a machine, agent configuration file, default recipient or topic, and do not ask again for an already approved send. Prefer one concise message with outcome, relevant evidence and material follow-up; send a full report only when requested (the sender may split it). Choose the status that reflects the actual result and verify delivery rather than equating queued work with a successful send. Structure and status values: [report guidance](report-reference.md).

## Hook timers

The hooks read settings from the process environment (seconds); inspect and change them through the active agent's supported configuration interface, without assuming an agent, config path or writable plugin cache. Unset variables use the defaults.

| Variable | Default | Purpose |
|---|---:|---|
| `TG_NOTIFY_PERM_THRESHOLD` | 1200 | Minimum time before a permission notification |
| `TG_NOTIFY_IDLE_THRESHOLD` | 1200 | Minimum time before an idle notification |
| `TG_NOTIFY_DELAY` | 1800 | Notification delivery delay |
| `TG_NOTIFY_DEBOUNCE` | 300 | Minimum interval between notification schedules |
| `TG_NOTIFY_STOP_THRESHOLD` | 1200 | Minimum task duration for a stop notification |
| `TG_NOTIFY_STOP_DELAY` | 1800 | Stop delivery delay |
| `TG_NOTIFY_STOP_DEBOUNCE` | 1200 | Minimum interval between stop schedules |

Set only the requested values, preserving unrelated configuration. `TG_NOTIFY_ENABLED=0` (also `false`, `no`, `off`, case-insensitive) disables new lifecycle notifications; changing the environment does not cancel notifications already scheduled by an older process, so inspect and cancel pending work through the supported runtime interface when authorized. Confirm which environment the hooks actually inherit (some agents need a new process or session) and report configured values separately from an actual delivery test, which needs authorization for the specific test and destination. Inspect state or logs without exposing tokens, destinations or message contents.
