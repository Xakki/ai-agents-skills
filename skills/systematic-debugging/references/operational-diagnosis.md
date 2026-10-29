# Operational diagnosis

Determine the exact service, instance, effective configuration, deployment identity and permitted observation interface. Check whether the affected process is actually running, can receive work, and uses the expected current configuration; intended files or a container marked healthy alone do not prove those predicates. Match logs and metrics by component and time; distinguish historical errors from new ones and transport acceptance from storage readback.

Before replaying a request, sending a message, changing a configuration or restarting a process, establish the task's authorization and whether the action is needed. Prefer a narrowly scoped, secret-free synthetic probe and an independently observable result. A timeout, missing result or empty log remains unknown until the observation instrument is shown to work.

For a hanging startup, trace parent/child lifecycle, resource locks, deadline and the actual exposed stage. If designing a diagnostic harness is in scope, bound its process and output, preserve child and wrapper outcomes separately, and verify cleanup of only owned resources. Do not imply that a diagnostic wrapper can supervise escaped processes or substitute for the real service readiness check.
