# Data, network and cutover

Identify in-scope databases, volumes, object storage, queues, scheduled jobs and active workers separately from the project directory. Define snapshot/restore consistency, write quiescence or replication point, ownership, permissions and verification before an authorized copy. A successful file copy does not prove that persistent data or external objects were transferred. Preserve an agreed rollback and recovery source until actual acceptance and retention conditions are met.

Inventory service identities, certificates and registrations: distinguish identities that must move from those that must remain unique. Avoid simultaneous consumers or writes when the service contract forbids them. Record relevant schedules, time zones and dependencies; transfer, enable or disable only jobs within the approved phase.

For authorized traffic changes, validate the destination through the requested route before changing DNS or proxy configuration. Verify relevant address families, certificate/SNI, trust and sanitation of forwarded headers, and expected propagation limits. Observe workload egress through its actual network context when access lists depend on egress; do not infer the observed address from a host interface or DNS record. Keep source rollback, destination mutations and post-sync writes in the plan.

Read back only the authorized external target after cutover and distinguish local readiness from actual end-to-end service behavior. Cleanup, revocation and source retirement are separate effects; do not infer permission from a successful destination check.
