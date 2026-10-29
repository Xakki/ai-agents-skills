# Adjacent transition and lint

Read the complete card and board definitions. Where `test` is the remaining-QA stage, `progress → test` can reflect locally verified implementation with explicit live gates still pending; `test → ready` requires evidence for every criterion at its required scope. Do not chain moves merely because a helper allows them or infer rollout authorization from a handoff.

1. Resolve the board and canonical helper through the project interface. Inspect selector, exact paths, card tracking and staging effects before invoking it.
2. Run targeted lint if supported; verify that it checked the intended exact card, and require exactly one card when the helper promises a single-card selector. Capture whole-board diagnostics separately, including paths and messages, not just totals.
3. Perform only the authorized adjacent transition. Confirm the source is absent, one destination exists, and each status field actually present agrees. Do not invent missing status fields.
4. Lint the destination and compare whole-board diagnostics with baseline. New move-caused failures block handoff; existing unrelated failures remain visible. Read back evidence and check siblings and the index; retain untracked status and index unchanged when staging is outside scope.
5. Report previously accepted counts as historical, separately from checks actually executed here. Name remaining metrics and exact acceptance conditions from the card; do not invent thresholds or permission to collect live evidence.
