# Continuity and evidence

When resuming an interrupted or paused epic, reconcile the current request,
authorization, child stage, active processes, owned changes and remaining gates.
A status request during an explicit pause does not resume work. Reuse a pending
process rather than starting a duplicate; reuse the responsible executor when
available and appropriate. Carry forward evidence only for unchanged inputs,
identify the exact missing predicate and continue only within the authorized
scope. Distinguish cancellation, runtime limits, failed gates and native refusals.

Reconcile the full Git index and worktree before changing branches, delegating
writes or staging a commit. Respect the repository's branch conventions and
user-selected workspace; preserve unrelated staged and untracked work. Inspect
the actual commit and paths when a delegated commit is part of the task.

If implementation unexpectedly contacts an external system outside the
approved scope, stop the affected external activity, report the observed effect
and resolve authorization before continuing it. Check the actual task and project
instructions for already-granted permissions rather than inferring permission
from credentials or asking again for an existing grant.
