---
name: generated-artifact-testing
description: Verify dynamically produced code or serialized artifacts at their actual consumer boundary.
---

# Generated artifact testing

Use when correctness depends on a generated script, query, document, schema or other artifact, rather than only its builder. Identify the actual producer, input, artifact, consumer and supported execution or validation environment. Preserve source state and avoid connecting to real external services or reading secrets unless the task authorizes it.

Exercise the production generation path with controlled inputs; inspect or validate the emitted artifact using the intended consumer where practical. Avoid duplicating the builder in the test as its only oracle. Test meaningful syntax, shape, behavior and relevant negative cases; report what is static, mocked, executed or untested. Run focused and required project checks using supported interfaces.

Use test-only data and isolated outputs for side-effecting artifacts. A synthetic parser or emulator proves only the behavior it faithfully models; report differences from the actual consumer. Follow the project's policy for generated outputs and preserve unrelated files.
