# Stash provenance and preservation

Use when asked whether stashed work remains unique, was integrated or can be retired. Inventory full stash object IDs and parents first: numeric selectors change after deletion. A stash can separately contain working, index and untracked layers. Inspect path metadata before content and restrict all historical reads to the authorized, non-opaque scope.

Compare each permitted layer with pinned committed history, current worktree and surviving refs. Distinguish exact committed inclusion, inclusion only in the working tree, an integrated change later superseded, a unique relevant change and unknown. A duplicate component or an old task status does not prove the entire stash is redundant. Record uninspected protected content as unknown.

Read-only analysis does not authorize applying, dropping or clearing a stash. For separately authorized removal, pin the approved object IDs and re-resolve the current selectors immediately before each native operation; stop if a selector no longer matches, a command is refused or state changes unexpectedly. Confirm requested IDs are absent and all keep IDs still present, then verify the relevant HEAD, index and worktree against the removal-phase baseline. Do not perform garbage collection or create backup refs without appropriate authorization.
