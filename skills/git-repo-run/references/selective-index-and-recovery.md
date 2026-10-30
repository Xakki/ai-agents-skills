# Selective index content and recovery

Use when an authorized artifact shares a file with an excluded hunk, a staged rename has later destination edits, or a commit/index operation was interrupted.

Capture the responsible actor's pre-mutation baseline: exact scope, HEAD, full staged records with modes and blob IDs, authorized working bytes and both rename endpoints. Do not read or copy secret or otherwise opaque content beyond its admitted boundary. Treat `RM` or `MM` as a staged change with further working changes, not as a complete candidate.

For a partial-file candidate, use a project-supported, previously verified hunk-selection or isolated-index mechanism. If an explicitly authorized scratch candidate is used to prepare an index blob, retain the actual file mode and pre-existing index content; review the complete cached path set, blob/mode and diff as well as excluded worktree bytes. Validate the mechanism and the normal hooked commit path in a disposable repository first. A private temporary index is valid only if all relevant hooks and container mounts demonstrably inspect that candidate.

For a whole-file candidate, staged destination bytes, source removals, modes and final authorized content must all match; names alone do not establish that later edits were staged. When staging a renamed card or document, re-read the helper's final destination body before committing.

After an interruption, confirm the writer and descendants actually exited; retain native failure evidence and compare current HEAD, complete index and relevant working bytes to the original baseline and intended candidate. Reuse only evidence covering the observed scope and exact bytes. Correct only a separately authorized scope; never reset, replace or reconstruct a shared index without proving foreign entries are preserved and having the required authority. A native security refusal is a stopping boundary, not a reason to retry through a different executor. Verify the final commit parent, message, changed paths, blobs and remaining staged and working state independently.
