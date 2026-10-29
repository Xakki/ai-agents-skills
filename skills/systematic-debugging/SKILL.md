---
name: systematic-debugging
description: Investigate failures with evidence, test causal hypotheses and verify repairs or authorized mitigation; отладка, причина ошибки.
---

# Systematic debugging

Establish the reported symptom, affected scope, current state, constraints and relevant recent changes. Preserve the actual error, input, timestamps and prior attempts; do not disclose credentials or restart a service merely to begin diagnosis. A working health endpoint does not prove readiness or an exercised user path.

Build the smallest useful feedback loop. Reproduce the failure when practical and permitted, then locate the first failing boundary using direct observations, comparisons and explicit hypotheses. Use available project and runtime interfaces; do not assume a host path, backend tool, provider, or ability to change settings. For intermittent or unavailable reproductions, state the sampling and uncertainty. Choose the next bounded probe by what it can distinguish, and do not repeat unchanged failures without a new reason.

Prefer the smallest fix addressing an evidenced cause. In an incident, an authorized bounded mitigation may precede complete root-cause analysis; identify it as mitigation and record the remaining uncertainty. Never weaken controls or bypass an approval refusal to make a probe pass. Preserve unrelated work and retry limits.

Verify the final candidate against the reported symptom and proportionate required checks. Distinguish an observed failure, a plausible explanation, a demonstrated cause, a local fix and a validated runtime outcome. For startup or deployed-service boundaries, read [operational diagnosis](references/operational-diagnosis.md).
