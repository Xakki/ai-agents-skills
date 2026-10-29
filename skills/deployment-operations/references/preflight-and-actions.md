# Live preflight and bounded actions

Translate the exact approved operation into target identity, allowed and forbidden effects, prerequisites, candidate, expected state, deadline and action budget. Inspect the actual command contract and permitted state without reading or logging secrets. Check relevant dependencies and effective runtime before an action, not just staged source. A preflight produces evidence for the requested decision; it does not perform the mutation or grant new access.

Do not assume a command labelled dry-run is side-effect free: inspect the actual runner's documented semantics and nested commands before using it as a read-only probe. A successful configuration render establishes the rendered candidate, not that the running service applied it.

When an operation has a fixed number of external actions, maintain separate entries for preparation, each probe, write and verification. Record whether a failed command reached the external boundary; a local setup failure is not an external response. Preserve real exit, timeout and receipt independently. Do not silently retry an ambiguous write or spend another one-shot attempt; reconcile only through separately permitted readback.

A limit on selected items is not necessarily a limit on external requests: account for internal retries, credential refresh, transport rotation and concurrent callers when the actual contract bounds attempts. A single-flight assertion must cover the real shared execution boundary, not only one command's local loop.

For a failed preflight, preserve the exact stop boundary, identify which checks ran and inspect only authorized bounded state. Do not dispatch, restart, clean up or change durable state merely to explain a stopped operation. Do not infer that absent logs or a healthy service prove an unexecuted action had no effect unless the actual observation can establish it.

If admission relies on time-limited receipts, check their source binding and historical integrity separately from freshness at the decision's authoritative clock. A valid old receipt does not establish present admission, and expiration does not erase the historical result. Preserve one-shot attempt state and prepare dependent work before requesting any new short-lived evidence.
