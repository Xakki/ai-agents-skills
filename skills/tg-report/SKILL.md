---
name: tg-report
description: Send an authorized completion or task report to a configured Telegram topic; отправить отчёт в телеграм, отчёт по задаче.
---

# Telegram report

Send only when the user explicitly requests the message or a previously authorized workflow covers the recipient, topic and report. Use the available [Telegram sender](../tg-notify/SKILL.md), resolving the plugin root and configuration through the active runtime's supported interface. Do not assume a particular machine, agent configuration file, default recipient, or topic.

Resolve `TELEGRAM_NOTIFY_CHAT_ID` and the requested topic (`TELEGRAM_NOTIFY_TASK_THREAD` for task reports or `TELEGRAM_NOTIFY_COMPLETION_THREAD` for completion reports) from the configured environment or credential interface. If routing is ambiguous or a required destination or topic is absent, obtain the missing information before sending; do not silently fall back to another chat or topic. Use the task's existing authorization rather than asking again for an already approved send.

Prefer one concise message with the outcome, relevant evidence and material follow-up. Send a full report only when requested; the sender may split it into multiple Telegram messages. Supply message content through a supported input channel rather than placing secrets or sensitive report text in command arguments. Choose the status that reflects the actual result, and verify delivery rather than equating queued work with a successful send. See [report guidance](reference.md) for structure and status values.
