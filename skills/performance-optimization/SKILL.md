---
name: performance-optimization
description: Measure and improve web application performance using representative workloads; производительность сайта, оптимизация скорости.
---

# Web performance optimization

Establish the user-visible goal, baseline, affected paths, workload and constraints before choosing an optimization. Use representative field data when available and controlled synthetic measurements for reproducible diagnosis; report missing samples and measurement limits rather than treating proxy metrics as proof of user experience.

For web experiences, evaluate relevant current Core Web Vitals (LCP, INP and CLS), network and server latency, payloads and runtime work. Confirm current metric definitions and thresholds from the authoritative documentation for the relevant tool. Measure the actual bottleneck before selecting rendering, caching, code-splitting, asset, database or infrastructure changes; server rendering, preloading, a particular CSS naming convention or a service worker is not a universal win.

Preserve correctness, accessibility, security and existing behavior. Where caching or data partitioning changes, verify freshness, invalidation and authorization boundaries. Compare the same workload and environment before and after; record commands, sample sizes, distributions, effects and remaining regressions. Deploy, change infrastructure or run expensive load tests only within the authorized scope.
