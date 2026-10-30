# Measurement and experiment contracts

Use when the card's outcome depends on performance, request counts, telemetry, or owner comparison of experimental variants.

Define the counted event at its execution boundary: logical work, submitted jobs, target attempts, redirects, retries, returned pages and artifacts are different populations. Trace producers and consumers and identify exclusions before selecting aggregation or claiming exact totals. Bound metric dimensions; avoid credentials, concrete URLs, dynamic identifiers and raw errors as labels.

Record the baseline, workload, environment, observation window, sample count, units, aggregation, skips, variance and the owner's actual thresholds. Compare repeatable before/after runs when a speedup is claimed. Distinguish configuration ceilings from measured runtime resource use, and estimates from observations. Preserve coverage and isolation rather than choosing a faster but unrepresentative test.

For experiments whose production choice comes later, define the fixed fixture, variant, normalized inputs, redacted outputs, measurements and owner verdict. Keep the existing production policy until an authorized decision; the experiment can be implementation-ready if the later decision is explicitly a separate post-execution gate. Do not invent numerical budgets or claim an unmeasured outcome.

Define ownership, delivery and deduplication, expected telemetry loss, and failure boundaries when accounting spans processes. Put acceptance at the actual proving layer, with deterministic failure and retry cases. A card or fixture cannot authorize remote changes, live probes or rollout.
