# Local lifecycle state and ownership

A security or availability gate needs distinct results for present, explicitly absent and inspection failure; only a documented not-found condition means absence. Permission errors, malformed state, unknown object type and unsupported protection are not equivalent to absence. Validate schema and object identity before consuming state or mutating lifecycle records.

Use appropriately bounded reads and stable handles. Recheck identity and relevant metadata after reading when concurrent modification matters. Treat pathname replacement and in-place descriptor mutation as distinct observations: an old descriptor can remain readable after rename, and replacement may also change old inode metadata. Diagnose a flaky classification with bounded tests of both cases before adding sleeps or attributing the symptom to infrastructure.

When the diagnostic contract distinguishes path replacement from in-place mutation, compare the current path identity with the original object before classifying changes to the retained descriptor: a replacement can itself alter the old inode's metadata and otherwise be mislabeled as an in-place write. Preserve both checks and test both branches. If a gate considers several paths, ensure an earlier present path does not suppress a later inspection error where the contract requires fail-closed behavior.

Matching size, inode and timestamps alone do not always prove bytes stayed unchanged during an in-place rewrite. Where the threat model requires content integrity, test same-size mutation and use a qualified immutable snapshot or integrity check permitted by the read boundary; do not assert a byte comparison for content that must not be read.

For leases or owner records, identify the exact target through a read-only projection and confirm that the selected reader does not prune, create locks or otherwise mutate. Compare process identity and start information under the actual platform contract; PID existence or acquisition age alone does not prove a live owner is idle or a lease expired. Missing evidence remains unknown. Preserve the owner record and distinguish diagnosis from separately authorized termination, cleanup or takeover.

Exercise malformed/oversize state, symlinks, nonregular files, replacement after open, directory swaps and cleanup races with an outside sentinel. Assert no forbidden outside read, write or unlink and no unauthorized child action, not merely an error return. Preserve the application's documented normal and stale-state semantics.
