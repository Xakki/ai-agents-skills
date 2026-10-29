# Readiness and review for an autonomous epic

For each complete candidate, report READY, BLOCKED, or HIDDEN-RISK; cite actual boundaries, dependencies and permitted ordering, minimum verification, and whether independent children are needed. A todo stage is not evidence of readiness. Treat open business choices, uncertain live-data scope, missing authoritative inputs, unsupported acceptance claims, and organizational or historical cards as blocked or exceptional; do not silently implement an umbrella card.

Decompose by independent responsibility and acceptance criteria, then sequence shared contracts before their consumers. Delegate concurrent work only to non-overlapping ownership areas, when authorized, and honor explicitly required profiles and commit policies. Do not invent a universal trailer or mandatory commit where none is authorized.

After implementation, obtain the required independent read-only review of the complete diff and call sites. A failing review blocks readiness. Repair only in-scope defects, preserve required history, repeat affected checks and independent review, and confirm earlier blockers are resolved. Separate lifecycle changes from implementation changes when required and preserve other actors' staged content.

Use safe dry runs and real dev checks when appropriate. Explain the limit of static or syntax checks where an actual UI interaction was not run; execute affected-area gates early and any required full integration gate before acceptance. Record live operational effects only when actually observed and authorized.
