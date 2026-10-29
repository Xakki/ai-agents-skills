---
name: publish-artifact
description: >
  Publish a self-contained HTML artifact or page to a self-hosted static site
  with a project make publish-artifact target, then return its public URL.
---

# publish-artifact

Copies a complete/standalone HTML file into the configured project's artifact directory; that
project's nginx serves it at `<BASE_URL>/artifact/<slug>/`. No docker build/deploy involved — plain
file copy, picked up immediately by an already-live static/alias location.

## Config

Resolve the project directory from the runtime's supported configuration interface:

```
ARTIFACT_PROJECT_DIR=/path/to/project   # the project whose Makefile has `publish-artifact`
```

## Happy path (the one command)

```bash
make --no-print-directory -C "$ARTIFACT_PROJECT_DIR" publish-artifact ART=<abs-path-to.html> [SLUG=<slug>]
```

Capture the **last stdout line** — that's the public URL. `--no-print-directory`
keeps Make's directory messages out of that position. Fetch the exact public URL
and compare its body with the authored HTML before reporting publication success;
account for intentional wrapping when publishing a fragment.

## Publication notifications

Follow the owner's configured Telegram routing, not a hardcoded DM or Saved
Messages destination. When `telegram-ops-notifications` is available, load it
and use its verified Gateway helper with `--kind notification`. Its notification
topic is authoritative; never fall back to a DM, General, another topic or sender.
Keep private chat IDs and credentials in that owner-local skill, not this shared
plugin. Do not read a Hermes credential store directly or create another sender.

When the user explicitly authorizes a notification to the configured recipient,
after successful public readback send one concise, quiet notification containing
the session ID, actual findings and the bare public URL on its own final line.
Resolve the helper through the active runtime's supported skill interface; if it
is unavailable, report the notification as not sent. Run its read-only
preflight and offline payload check, then send the authorized message with a
stable event ID. Verify the returned sender, chat, topic and message ID; perform
exact-message readback when the configured user connection is available.
An ACK alone is not independent readback. Preserve an uncertain send outcome;
do not resend with a new key or change the route on access/policy refusal.
Return the URL to the user even when publication succeeded but notification
verification remains incomplete, distinguishing both outcomes.

## Explicit publication smoke tests

When the owner requests an end-to-end test, use a fresh slug and a clearly labeled
standalone test report with a unique nonsecret marker. Do not overwrite an existing
report or claim Telegram delivery in the page before it has been verified.
Compare the complete public response with the authored document. If a notification
is separately authorized, send it once with the same marker and the bare report URL
as the final line. Use the owner's
notification skill for identity, routing, credentials and access checks; do not
embed private destinations or provision access in this shared skill.

Record publication/readback, notification preflight, sender ACK and independent
message readback separately. A saved Bot credential is not a successful preflight.
If preflight is refused, preserve the published URL and report notification as not
sent; do not change accounts, grants, API authorization or send paths to force the
test through. Do not republish or resend solely to turn an incomplete check green.

## Note on fragments vs. complete docs

The target auto-wraps a headless Artifact-tool fragment (no `<html>`/`<head>`/`<body>`) into a full
HTML5 document (charset, viewport, title). A file that already contains `<html` is copied as-is.

## Safety (mirrors the Artifact-tool policy — keep it short)

- Only publish self-contained HTML: inline CSS/JS, no external hosts (fonts/CDNs/fetch targets).
- Never publish pages impersonating a real person/org, fabricated records/reviews, or flows that
  collect credentials/payment under false pretenses — refuse, and don't suggest alternate hosting.
- Read any file you didn't author yourself, in full, before publishing it.

## Bootstrapping a new project

See `reference.md` for adding this capability (script + Makefile target + nginx location) to a
project that doesn't have it yet.
