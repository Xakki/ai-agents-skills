# Schema verification

For operation-level security metadata, compare the generated scheme and inheritance with actual route access rules and canonical declarations. When the issue is documentation metadata only, avoid changing the runtime authorization policy or global security composition. Test both explicitly public operations and protected operations so an apparently fixed public route does not hide weakened protection elsewhere. Use the project's supported generation or schema route and distinguish an unchanged generated artifact from one that was not checked.

When a generator's default output is unwritable, first inspect the runtime, mounts and existing consumers. If the task authorizes changing its interface, retain the existing default and add a configurable writable output path. Verify an explicit path and the original default in suitable environments; parse the result and check the expected schema and paths. Do not claim an offline or secret-free generation unless the actual execution supports that claim.

When documentation is partitioned by audience or permission, check each published area's expected route set and reference resolution against the actual authorization boundaries. Verify that restricted routes are absent from less-privileged outputs and that private documentation cannot be served across users by a shared cache.
