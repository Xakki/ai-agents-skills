# Secret configuration sources

Trace the real loader, selected file, process environment, launcher and any orchestrator interpolation separately. Service-owned credential files, project files and injected environment are different sources; a global disable switch can suppress more consumers than the failing one. Verify the documented precedence and distinguish unset from explicitly empty values. Never print a resolved production configuration or read secret values merely to diagnose precedence.

Before attributing failure to a loader, establish whether the selected service has the required setting through an authorized status-only observation and inspect its public setup template. Test conflicting process, orchestration and dotenv values using disposable harmless fixtures; confirm the selected project and service before interpreting results. Prefer a narrow path or error-handling change appropriate to the actual service contract over disabling all loaders. Preserve established valid authentication and report startup readiness separately from provider availability.

Do not infer security of a file from POSIX mode bits on platforms or mounts that do not enforce them; use the relevant platform permission model. Read-only review does not authorize credential replacement or weakening access controls.
