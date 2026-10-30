# Telegram report guidance

Use an action-oriented title and concise, factual outcomes. Include a commit, review link, path, service or follow-up only when relevant and appropriate for the recipient. Clearly distinguish completed, partial, failed and deferred work; do not include credentials or unnecessary private content. A full report may include supporting diagnostics when requested and appropriate for the destination.

The sender accepts status values `ok`, `warn`, `fail` and `info`. Use `warn` for material caveats, `fail` for an incomplete task, and `info` for a neutral update. Plain mode can be used when mentions must be parsed outside an HTML preformatted block.

Resolve the runtime's credential and destination settings through its supported interface. The sender's environment takes precedence over its own configured credentials file for the variables it explicitly supports. Do not assume that a third-party agent reads the same configuration or that a destination identifies a private chat.
