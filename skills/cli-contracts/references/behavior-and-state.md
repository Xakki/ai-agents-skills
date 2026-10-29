# CLI parsing, output and state

Check missing, unknown, malformed, mutually exclusive, repeated and unexpected arguments according to the actual contract. Test help independently, including unusual trailing input, without starting protected services or making network calls. Preserve the documented stdout, stderr and exit behavior; do not globally assume that every CLI uses JSON or a particular error code.

Map every output path for tokens, codes, URLs, credentials and provider errors, including callbacks, logs and tracebacks. Test with synthetic sentinels at the real CLI boundary, preserving meaningful sanitized stage and outcome. An empty output is not necessarily a useful or correct failure. A valid-looking fake credential may be persisted by a storage command: use fixtures that cannot reach an unauthorized real store.

For stateful commands, test the changed operation followed by the first dependent action, plus alternate initialization order, persisted defaults, explicit overrides, collision and reset behavior. Separate session workspace from launch cwd and shell navigation. Check actual persisted state and downstream resolution, not only an echoed fake payload. Preserve valid normal workflows while testing refusal paths.

For operator mutations, separate read-only inspection from explicit actions and enforce required context inside the real command, not only in its wrapper. Treat every Make/shell variable as untrusted; pass through a supported structured argument, environment or stream and validate before using it, rather than interpolating it into executable shell text. Map refusal or ambiguous outcome to the documented non-success status; test that invalid inputs make no protected calls.
