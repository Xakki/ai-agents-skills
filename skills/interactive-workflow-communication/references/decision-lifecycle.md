# Decision lifecycle research

Use when investigating or designing an interactive request, approval or reminder flow; do not infer runtime support from this checklist.

Trace the actual authorization gate and request owner before the UI. Distinguish a non-overridable policy floor, a human approval request, an ordinary clarification and a notification. Identify which processes and client surfaces can present and settle each request, whether request IDs and deadlines survive reconnect, and whether cancel or stop rejects late continuation. A parent message does not automatically settle a child process's native request.

Check the current implementation and authoritative runtime contract. Reconstruct a preserved decision from the exact question and response, not from a truncated summary or a proposed profile name; recover only the necessary bounded history. A timed-out or empty answer is not consent. Preserve an earlier valid choice and ask a narrow clarification only if competing pending questions leave the answer ambiguous.

Separate human waiting, reminder thresholds, automated decision budgets and authorization expiry. A reminder is not a decision or approval. End or cancel pending reminders when their request is settled, where supported. Distinguish an agreed design, installed configuration, exercised runtime behavior and a merely source-based hypothesis.

For configurable choices, bind the resolved action and scope to each request so later edits cannot reinterpret a pending or cached decision. Verify the actual interactive flow and the supported cancellation path before claiming end-to-end readiness. Model instructions alone cannot guarantee that a host displays a control or enforces a security gate.
