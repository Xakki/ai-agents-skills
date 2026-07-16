---
name: publish-artifact
description: Publish a self-contained HTML artifact/page to a self-hosted static host (via a project `make publish-artifact` target) and return its public URL. Триггеры RU: «опубликуй артефакт», «выложи артефакт», «захостить HTML-страницу», «дай ссылку на артефакт», «опубликуй на xakki.pro»; EN: "publish artifact", "self-host this page", "host this HTML", "give me a public link".
---

# publish-artifact

Copies a complete/standalone HTML file into the configured project's artifact directory; that
project's nginx serves it at `<BASE_URL>/artifact/<slug>/`. No docker build/deploy involved — plain
file copy, picked up immediately by an already-live static/alias location.

## Config

Read from `~/.config/artifact-publish/.env` (chmod 600, not in any repo):

```
ARTIFACT_PROJECT_DIR=/path/to/project   # the project whose Makefile has `publish-artifact`
```

## Happy path (the one command)

```bash
source ~/.config/artifact-publish/.env
make -C "$ARTIFACT_PROJECT_DIR" publish-artifact ART=<abs-path-to.html> [SLUG=<slug>]
```

Capture the **last stdout line** — that's the public URL. Return it to the user. (Everything else
the target/script prints goes to stderr, so the last stdout line is always exactly the URL.)

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
