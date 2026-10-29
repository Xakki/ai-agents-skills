# Hermes named-profile routing

When a task or applicable project instruction requires a named Hermes profile,
establish that profile's identity, availability and permissions through the
runtime's supported interface. If the required profile cannot be used, report
the dependent work as blocked; do not substitute an anonymous delegate.

If the runtime supplies the `herm-prof` skill for named-profile launching, use
its documented interface. Do not invent a launcher or force model/provider
overrides into a profile launch; preserve explicit task and runtime requirements.
If no such interface is available, report the limitation rather than assuming
Hermes-specific commands work in another agent.
