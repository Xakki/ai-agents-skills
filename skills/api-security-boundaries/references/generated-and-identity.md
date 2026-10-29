# Generated security contracts and identity acceptance

For generated API security, compare canonical source, route access, generated operation metadata and actual runtime behavior. Where inheritance applies, check each operation's effective security, including explicit anonymous overrides. Verify audience-specific path inclusion and exclusion, authenticated routes and appropriate cache-control behavior according to the project contract. A source annotation or generation command alone is not proof of the resulting document.

Inspect referenced scheme definitions and shared components, examples and descriptions recursively in every published audience, not only filtered routes. Verify referenced schemes resolve within that document and that private or orphan definitions are not unintentionally published. Derive expected authorization and relevant 401/403 behavior from an independent runtime authority where available; a second hardcoded route-prefix table can reproduce the same incorrect assumption as the generator.

When testing multiple anonymous or guest identity paths, establish each actual source of identity and precedence, then trace the request to its durable owner and resulting side effects. Use isolated synthetic identities and vary relevant input so one fallback cannot accidentally prove another. Test forbidden scopes and proxy-header trust where applicable, clean only fixture-owned data and avoid counts shared with unrelated work.

In independent review, use current candidate evidence, not solely implementation claims. Distinguish a compiled or generated contract from successful live access, and a receiver acknowledgment from a sender's local callback. Do not add real traffic or mutable operational actions without authorization.
