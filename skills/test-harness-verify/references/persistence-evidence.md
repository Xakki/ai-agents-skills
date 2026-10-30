# Persistence evidence

Identify the actual isolated test store, migration state, public entrypoint and relevant transaction boundaries. A mocked repository or generated schema may not exercise the real persistence, constraints or migrated historical rows. Keep shared and production data outside the admitted test scope.

Where required, test successful updates and each materially distinct invalid ownership, version or expiry case against the real supported boundary. Pair a rejection assertion with evidence that protected persisted state did not change; compare all relevant values, not only a status field. For a transactional multi-step operation, a controlled failure after an intermediate change can test whether all intended changes roll back, when the fixture can safely produce that failure and the probe is authorized.

Use the store's actual clock and precision for fence or expiry assertions where relevant rather than relying on fragile sleeps. Keep fixture lifecycle, attempt counts and cleanup scoped to owned test resources. Report focused tests, broader suite results, unrun cases and remaining integration limitations separately.
