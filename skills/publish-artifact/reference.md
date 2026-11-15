# Publisher integration contract

Use the project's existing interfaces first. Record the chosen configuration in the
appropriate project or owner-local environment, never in the shared skill. The following
names describe settings, not a required implementation:

- `ARTIFACT_BASE_URL`: project public HTTPS base URL, including any route prefix.
- `ARTIFACT_PUBLISHER`: project publisher executable or supported integration.
- `ARTIFACT_GLOBAL_BASE_URL`: shared public HTTPS base URL, including any route prefix.
- `ARTIFACT_GLOBAL_PUBLISHER`: shared publisher executable or supported integration.
- `ARTIFACT_GLOBAL_DIR`: storage directory, only when required by that publisher.

Resolve each destination as a pair: project publisher and project URL, otherwise global
publisher and global URL when the project has no public domain. Partial or contradictory
configuration is an error, not permission to mix a project publisher with a global URL.
If the existing integration uses different variables or an API, adapt to its actual
contract instead of assuming these names are already implemented. Do not execute arbitrary
configuration as shell code; use an executable path and separate arguments, or the native
integration. Do not expose credentials in command arguments, logs, or public output.

When adding a publisher, define how it accepts an absolute input path, a project namespace
and a slug, reports the exact HTTPS URL and errors, and handles collisions and concurrent
writes. Preserve existing artifacts; reject overwrite unless explicitly authorized. Ensure
storage survives the project's ordinary deployments, and configure route, TLS, access and
permissions for the chosen backend. Support complete HTML as-is; if fragments are accepted,
document and verify their transformation. Do not expose auto-generated directory listings;
a listing is the script-maintained, password-protected index described in SKILL.md, with
its credential file stored outside the public directory and version control. Do not assume a particular web server, filesystem, container, build
tool, or URL path. Configuration changes do not by themselves prove live publication.

Check configuration and route ownership before activation. Verify the chosen hostname's
actual DNS records, certificate, ingress and backend, including each advertised address
family. Follow host and provider authorization rules for DNS and deployment. Verify an
actual authorized publication with a unique nonsecret marker and exact public response;
report separately any untested activation or readback. Do not publish a test page merely
because setup was requested if publication was not authorized.

For an executable configured through `ARTIFACT_GLOBAL_PUBLISHER`, the shared file
publisher contract accepts three separate arguments: absolute HTML input path, project
namespace, and slug. The publisher reads its own global environment and prints the exact
URL on stdout. For example: `"$ARTIFACT_GLOBAL_PUBLISHER" "$file" "$project" "$slug"`.
This contract is optional for other backends: use their documented interface instead.

The shared publisher may also keep the password-protected index. It then receives, from its own
environment, the index tool path and the credential file path (kept outside the public
directory), updates the index with `<project>/<slug>` after writing the page, and creates the
credential only when the file is missing, printing the password once on stderr. Report that
line to the owner immediately and never store the password elsewhere.
