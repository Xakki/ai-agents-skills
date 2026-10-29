# Dashboard operations

Resolve the actual authorized dashboard and datasource interfaces; do not assume a host, account, configuration path or vendor. Define the user's question and choose query, unit, time range and aggregation that match the stored data's semantics. Show labels and useful context while avoiding sensitive payloads.

Validate representative queries against the actual datasource and, when possible, read back the saved candidate. A query returning no series may mean no samples, a label mismatch, stale data or a failed pipeline; it is not necessarily zero. State how rate or window calculations behave for short-lived or sparsely sampled processes.

Distinguish dashboard design, source-controlled artifact, published dashboard and visual user acceptance. Saving or changing a live dashboard requires the applicable user authority; design work alone is not publication authority. Do not invent a browser or API capability and do not modify unrelated dashboards.
