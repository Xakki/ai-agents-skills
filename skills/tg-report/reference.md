# tg-report — reference

Read this for env-resolution details, report structure, and status semantics.

## Why process-env-first matters

`tg-notify.sh` sources `~/.config/tg-notify/.env` with `set -a`, which re-exports every
key — including empty ones. If the `.env` copy has `TELEGRAM_NOTIFY_CHAT_ID=` (even blank),
it clobbers the value already set in `~/.claude/settings.json` env block.

Remedy (shown in SKILL.md): capture `TELEGRAM_NOTIFY_*` into local vars **before** sourcing,
then use `${CHAT:-...}` to fall back to the post-source value only if the pre-source value was empty.

**Tip:** in `~/.config/tg-notify/.env`, keep the `TELEGRAM_NOTIFY_*` lines commented out (as in
`.env.example`). That way sourcing the file never risks overriding process env at all.

## Where vars may be set

Priority order (highest first):
1. Exported env vars — e.g. `export TELEGRAM_NOTIFY_CHAT_ID=...` in the shell.
2. `~/.claude/settings.json` `env` block — set once, applies every session.
3. `~/.config/tg-notify/.env` (chmod 600) — only for `TELEGRAM_BOT_TOKEN` and tg-notify defaults; keep `TELEGRAM_NOTIFY_*` commented here.

When the user provides a missing value, offer to persist it in `~/.claude/settings.json`.

## Report structure

**Title** (≤70 chars, action-oriented): `<server/repo/project>: <что сделано>`
- completion: `saFin: nginx certs renewed`
- task: `dev.sa: pagespeed CWV — fix CLS=0.39, fonts preload`

**Body (concise):**
- 1 line per outcome, prefix ✅ / ⚠️ / ❌.
- Include commit hash / branch / PR URL, touched paths, services, ports, URLs.
- End with a ⚠️ block if follow-up or risk needs attention.
- No narrative ("я сделал…"). Facts only.

**Body (full):** same, plus diagnostics — errors encountered, root causes, config paths
touched, before/after values, log excerpts.

## Optional mention

Reports default to `-p plain`. If the user includes `@username`, place it as the
**first line of the body**. Plain mode is required here — HTML mode wraps the body in
`<pre>`, which breaks Telegram's @mention parsing.

## Status flag (`-s`)

| Value | When |
|-------|------|
| `ok`   | everything succeeded |
| `warn` | succeeded with caveats / partial / manual follow-up needed |
| `fail` | task did not complete |
| `info` | neutral status update (rare) |
