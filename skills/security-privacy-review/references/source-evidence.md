# Source-only credential evidence

Limit inspection to explicitly authorized source paths; do not expand to dotenv files, vaults, global credentials or live authentication. For an authorized credential-bearing source, parse narrowly in memory and emit only a fixed purpose/type, location and masked representation. Tool output, logs and delegated prompts are disclosures too. Do not retain a raw source copy as an evidence artifact.

Verify syntax and context before identifying a credential: a heading, table name, placeholder, hash or environment reference is not automatically a plaintext password. Separate seeded development values from personal/service access. Compare any reuse only between verified candidates in memory and report grouped locations or boolean results without values. Do not infer that an observed literal is live, exposed externally or compromised without independently authorized evidence.

A source-only inventory is not a runtime redaction test and does not authorize changing source, accounts or secrets. State what was inspected and which validity or exposure claims remain unverified.
