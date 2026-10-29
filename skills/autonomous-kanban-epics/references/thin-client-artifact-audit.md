# Client and provider artifact audit

When removing an execution capability from a client or provider, verify that source, advertised capabilities, permissions or manifest, and all generated deliverables agree after the canonical build. Recursively enumerate relevant artifacts and assert the expected entry artifacts exist, so an empty build cannot pass the check.

Search all applicable direct and computed property syntaxes for removed APIs and product-specific capabilities. Self-test each detector against positive and negative synthetic samples. Run the actual canonical test, lint and build gates; document differences when a direct command uses other environment or version inputs. A remaining capability must be intentionally retained and documented, or proposed as a separately authorized follow-up. Static source checks do not prove generated artifacts or live behavior.
