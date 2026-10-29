# Backend review boundaries

Map the requested request or event through authentication, authorization, validation, business logic, persistence, caches and asynchronous work as relevant. Trace complete failure paths to observable consequences; code patterns or unusual names alone are not defects. Check whether errors occur before or after a committed effect, and whether retries, acknowledgements or cancellation can duplicate or lose work.

Inspect transaction and lock ownership, race boundaries, tenant scope, input normalization and migration compatibility when they apply. Check actual consumers and tests rather than assuming an interface declaration proves wiring. Distinguish intended source behavior from the effective running service and static review from executed evidence.

Verify only within the assigned read and execution scope. Use synthetic fixtures where needed and authorized; retain precise evidence for direct findings and separate untested risk, blocked validation and uncertain impact.
