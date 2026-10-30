# Shared-worktree race recovery

Use when concurrent writers leave unexplained changes, missing commits or unexpected branch state. Stop the affected coordinated writers, not unrelated permitted owner work. Retain handles and failures, wait for their actual exit, and preserve dirty paths and the pre-existing index. Continue review only on a fixed commit or complete immutable source/test snapshot.

Read the exact current branch, ref tip and relevant status under the allowed reader boundary. Compare these with the actor's entry baseline and observed outcomes; a changed timestamp or a missing final message does not identify the writer or prove data loss. Where authorized, compare relevant reflog entries, candidate commits and working bytes to establish reachability. Preserve blocked or opaque material without inspecting beyond its boundary.

Reconcile and restore only separately authorized content from verified evidence. Do not use reset, clean, checkout or amendment as an automatic repair. Validate that intended commits are reachable, owned files and any task state are consistent, excluded work remains intact, and the review receives the final immutable revision or manifest. A clean task-specific scope is not proof the whole shared checkout is clean.
