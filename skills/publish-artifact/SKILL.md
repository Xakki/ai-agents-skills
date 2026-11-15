---
name: publish-artifact
description: Set up project-specific or shared artifact publication and publish self-contained HTML with verified public readback, a script-maintained password-protected index and one-time password delivery. Use when asked to configure or publish an artifact or page.
---

# publish-artifact

Set up and use a publisher appropriate to the project and its actual infrastructure. A
publisher may be a project command, static server, object store, or other supported
backend; do not assume Make, nginx, a fixed route, or local file storage.

## Select and configure a destination

1. Inspect the current project's instructions and existing publication, domain, storage
   and deployment configuration. Reuse its supported publisher if suitable. A configured
   project publisher and public HTTPS base URL take precedence over global settings.
2. If the project has a public domain but no publisher, integrate one using its existing
   conventions and durable storage. Keep routes isolated and preserve existing behavior.
3. If it has no public domain, use the owner's configured global publisher and public
   HTTPS base URL. A URL alone is not a publisher: verify its matching write interface,
   routing, TLS, and project-specific namespace. If the global service is absent, set it
   up within the authorized infrastructure; select an unused owned name after checking
   DNS, TLS and routing. Wildcard resolution does not prove that a name is unused.
4. Resolve settings from the runtime's supported environment/configuration interface.
   On hosts that use `~/.bash_ai`, place owner-specific global settings there, without
   embedding credentials, domain names, storage paths or implementation assumptions in this
   shared skill. Existing processes may need a refreshed environment. Project settings
   override global settings; do not silently fall back when a configured project publisher
   fails. See [reference.md](reference.md) for the integration contract.

## Publish

Read the entire input before publication. Identify salary expectations, career history and
other personal or sensitive material in reports; publish only the content the owner explicitly
authorized and warn that anyone with the link can read it. A response-local `noindex` directive
is not access control. Include requested next actions in the artifact and distinguish planned
steps from completed effects. Publish a single HTML document with inline
CSS/JS and no assets that must be fetched from private or local paths. Links and
`<a href>` to external sites are allowed and expected in reports; external scripts,
styles, fonts and images are allowed too but make the page depend on those hosts, so
prefer inline for anything essential. Resources must use `https://` (browsers block
`http://` subresources on an HTTPS page). Check what the destination actually enforces
(publisher validation, a Content-Security-Policy header, `X-Frame-Options`, a size limit)
and read the page back to confirm it renders; do not assume the page is sandboxed.
Never publish impersonation, fabricated records/reviews, or deceptive credential/payment
collection. Invoke the selected publisher according to its documented contract, using a
unique project namespace and a nonconflicting slug. Read back the exact public HTTPS URL
and compare the complete response with the expected published document, including any
intentional transformation, before claiming success. Report the URL and any incomplete
verification. Publication is an external write and needs user authorization.

## Artifact index

A publisher that lists its artifacts keeps one index page under these rules:

- Only the publisher script writes the index, as part of each publication. Do not edit it
  by hand, regenerate it from a directory listing, or enable server autoindex. If a
  publisher lacks this step, add it to the publisher instead of patching the page.
- A new artifact is inserted at the top. Its row shows the creation date and time and the
  artifact's `<title>` as the link to the artifact (the slug when there is no title).
  Republishing an existing slug keeps the row's position and creation time and refreshes
  only the title.
- The index is rendered from a minimal self-contained template kept next to the publisher:
  no external hosts, `noindex`, readable on a phone. Change the look in the template, not
  in the generated page.
- Only the index requires a password. Artifact pages stay public: their URLs are shared
  with people who must not need credentials. Never put the protection on the whole route.
- The publisher generates the password when the credential store is first created, keeps
  only its hash outside the public directory and version control, and prints the plain
  password once. Deliver it to the owner right then: in the agent's reply, or through the
  owner's configured Telegram route when that was requested or nobody reads the reply.
  Never write it into a page, log, commit, card or shared notification text. Later
  publications print no password; do not regenerate an existing one unless asked.
- After setting up or changing the route, verify with real requests: the index refuses
  anonymous and wrong credentials, returns the stored page with the right ones, and an
  artifact page still opens anonymously. After each publication confirm the new row is
  first in the index.
- When reports link to external sites, serve them with `Referrer-Policy: no-referrer` so the
  report URL is not leaked in the `Referer` header.
- When artifacts move to another publisher, copy the directories first, rebuild the index
  from the original creation times, verify the new URLs, leave redirects from the old
  routes, then retire the old publisher and its settings; keep the originals as a backup.

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
