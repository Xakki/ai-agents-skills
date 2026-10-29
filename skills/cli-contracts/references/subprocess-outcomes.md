# Subprocess protocol and bounded supervision

Treat child stdout as an untrusted protocol where it represents an operational result. Validate the documented bounded schema, requested identity/version and consistency with the real exit status before persistence or publication. Do not assume zero exit means a requested effect completed. Sanitize raw stdout, stderr and exceptions before they cross a protected output boundary.

Preserve uncertainty: a wrapper timeout does not prove the child or its remote effect stopped. Before a separately authorized retry, verify the exact target and writer state. Rollback must identify and verify the intended previous version and its result; re-running a failed command is not rollback evidence.

For an owned, cancellable harness, use one monotonic total deadline across setup, operations, retry waits and permitted cleanup. Bound captured output while reading, and distinguish direct-child exit, descendant settlement, pipe EOF, reader and sink completion. Kill or signal only when the actual authorization and process ownership permit it; stopping a host container client is not proof of stopping the in-container workload. An observation deadline alone does not authorize termination.

Test malformed output, size overflow, mismatched identity and exit, already-applied state, ambiguous child completion, correct rollback reference and no shell injection using disposable fixtures. Report the child outcome, capture/cleanup completeness and unexecuted operator prerequisites separately.
