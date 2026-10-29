---
name: tg-notify
description: Send an authorized Telegram notification or short report to a configured chat, group, or channel; уведомление в Telegram, сообщить в телеграм.
---

# tg-notify

Manual sender of a Telegram message to a configurable destination (DM, group, or channel) via a bot.
The plugin also ships optional lifecycle hooks for long turns and permission/idle
prompts. This skill is the **manual** sender. Configure and enable hooks only
when authorized; hook installation alone does not authorize a message.

## When to use

Automatic completion notifications use the configured threshold, which defaults
to 20 minutes; unknown duration does not satisfy it. An explicit user request
to send a notification does not require waiting for that threshold.

Send only when the user explicitly requests it or an authorized scheduled or
background workflow covers the destination and message. A long task alone does
not grant permission to send.

Track duration honestly with `SECONDS=0; <command>; dur=$SECONDS` so the check is real.

## Main thread only

If you are a **subagent / teammate** (spawned with a task by another agent, no direct line to the
user), do **not** invoke this skill — return your report to the teamlead and let them decide. When
in doubt, assume subagent and hand the report up. (Auto-send hooks are unaffected; they fire on the
main session's lifecycle, not from inside a subagent.)

## How to invoke

Obtain the resolved `SKILL_DIR` and authorized destination through the runtime.
Use stdin for the message body so it is not passed in the sender's argv:

```bash
printf '%s\n' 'Deployment completed.' | "$SKILL_DIR/tg-notify.sh" -s ok -t 'Deployment'
```

Do not include secrets in the title or other command-line arguments. See the
reference for configuration, explicit destination and message authorization.

## Reference

Configuration (env vars, destination types), full flag table, and conventions live in
[reference.md](reference.md) — read it when you're actually sending.
