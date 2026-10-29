# Measurement evidence

Record build and fixture identity, environment and network boundary, whether the run is synthetic, local, staging or production, and any secret policy. Record conditions, exact arguments, run and sample counts, cadence, warm-up, window, delay and concurrency. Preserve raw observations in base units.

State the aggregation and independently verify its arithmetic, sample counts and unit conversion; 1 MiB is 1,048,576 bytes. Reject missing, unsupported and zero-sample input rather than silently aggregating it or dividing by zero. Pair deterministic fake-service checks with a real authorized local harness spot-check where possible, and label scheduler noise and reduced sampling as limitations. Keep historical multi-trial results separate from current verification and do not infer external feed, production performance or OOM conclusions without evidence.

A valid acceptance harness must distinguish the claimed behavior from ordinary reachability; fail closed when prerequisites fail and exercise the actual contract-specific endpoint and intended topology. A broken harness is not by itself proof of a product failure.
