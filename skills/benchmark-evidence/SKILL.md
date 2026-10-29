---
name: benchmark-evidence
description: Plan bounded benchmarks and verify measurement evidence against acceptance criteria.
---

# Benchmark evidence

Use for a benchmark or performance comparison where evidence informs a decision. Define the question, units, conditions, acceptance criteria, sampling plan, execution budget and permitted resource effects before running. Verify that trials compare the intended builds, workloads, inputs, configuration and resource constraints. A benchmark runner's availability does not authorize production tests, service changes or broad cleanup.

Retain raw per-trial observations and actual command outcomes. Verify schema, units, expected and valid sample counts, failures and substitutions. Recompute aggregates from raw values with a stated rounding policy; distinguish mean from worst observed value and record the actual measurement window. Instrument readiness, latency, shutdown or other required dimensions directly; one favorable metric cannot establish an unrelated criterion.

Report method, sample size, provenance, conditions, results, limitations and unmeasured criteria. Keep measured facts separate from interpretations and prevent cherry-picking. For noisy tests, incomplete runs or resource constraints, preserve the failure rather than treating an exit-zero wrapper or a subset as full acceptance. Remove only explicitly owned temporary resources when cleanup is authorized.

For data-access changes or index proposals, use [data-access performance](references/data-access-performance.md).
