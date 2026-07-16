# Bootstrapping artifact publishing into a new project

Three pieces, all self-contained (no new runtime deps):

## 1. `bin/publish-artifact.sh`

Contract:
- Usage: `publish-artifact.sh <html-file> [slug]`.
- Config via env, with defaults: `ARTIFACT_DIR` (served dir), `ARTIFACT_BASE_URL` (public origin).
- Validates the input file exists; warns (stderr) if it doesn't end in `.html` but still accepts it.
- slug: `$2` if given, else the input's basename without `.html`; sanitized — lowercase,
  spaces/underscores → `-`, strip anything outside `[a-z0-9-]`, collapse repeats, trim leading/
  trailing `-`. Empty after sanitizing → error, exit 1.
- dest = `$ARTIFACT_DIR/$slug/index.html`.
- If the input already contains `<html` (case-insensitive) → copy verbatim. Else wrap it: a full
  HTML5 doc (`<!doctype html>`, `lang`, charset + viewport meta, `<title>` — from the fragment's own
  `<title>` if present, else the slug) with the fragment as the `<body>` (its own leading `<title>`
  line stripped so it isn't duplicated). This is the important part — Artifact-tool output has no
  html/head/body wrapper.
- Regenerates a plain listing at `$ARTIFACT_DIR/index.html` (one `<a href="/artifact/<slug>/">` per
  immediate subdir), rebuilt fresh every run.
- Output discipline: all diagnostics to stderr; **only** the final public URL on stdout (last line),
  so callers can capture it with `$(...)`.

It's self-contained: no dependency beyond bash + coreutils, safe to drop into any project's `bin/`.

## 2. Makefile target

```makefile
publish-artifact: ## Publish an HTML artifact → <dir>, served at /artifact/<slug>/ (ART=file [SLUG=slug])
	@test -n "$(ART)" || { echo "usage: make publish-artifact ART=path/to.html [SLUG=slug]" >&2; exit 1; }
	@bin/publish-artifact.sh "$(ART)" "$(SLUG)"
```

Must not require docker — `ART=`/`SLUG=` only, plain shell. `SLUG` may be empty; the script already
treats an empty/absent `$2` as unset (`${2:-}`), so an empty make var doesn't crash under `set -u`.

## 3. nginx location + reload

Point it at whatever directory is durable across deploys in that project (survives rebuilds/
redeploys — a bind-mounted `public/`-style dir, not something wiped by CI). Add to the relevant
server block(s):

```nginx
location /artifact/ {
    alias /app-back/public/artifact/;
    index index.html;
    try_files $uri $uri/ =404;
}
```

Adjust the `alias` target to match the project's actual served-dir mount path. Then reload nginx
(project-specific — e.g. `make nginx-reload`) to pick up the new location.
