# Stage and acceptance

Resolve the canonical board and read the full card, decisions and evidence. Record approved scope and exact paths, stages, source pins and protected state before mutation. `progress → test` is permitted only when the project's implementation entry gates pass; outstanding live acceptance remains explicitly pending if that stage allows it. `test → ready` requires its actual acceptance and review gates. A local fixture is not live rollout evidence. Require explicit owner approval for `done` and separately assess merge, push, deploy and other effects.

Distinguish reviewer acceptance of an unchanged candidate from an unmet global gate, and bind reviews to a genuinely separate reviewer and the source actually reviewed. Preserve historical failures and separate source inspection from executed checks. Carry prior results only when source and runner inputs still match. Record owner-cancelled work without fabricating implementation or test results; do not replay accepted-card transitions merely to create history.

Serialize writers before freezing candidate bytes. An observation timeout does not complete or fail a live process; retain its handle, recover the native receipt and reconcile the current checkpoint before dependent work. A security or access veto stops the refused operation and is not a reason to change tools or weaken a safeguard.
