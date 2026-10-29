---
name: verified-findings
description: Verify defects, fixes, negative claims and test effectiveness; проверка находки, мутационное тестирование.
---

# Verified findings

State precisely what was observed and the boundary of the claim. Code inspection, static analysis, live execution and tests can establish different facts. Distinguish a direct finding from a hypothesis, and never imply that an unexercised path or an unavailable test has been verified. For a negative claim, define the searched or tested scope and confirm the observation instrument works.

Reproduce a reported failure when practical and proportionate before relying on its predicted cause. Verify a fix against the relevant behavior and final artifact; evidence that a defect was reproduced is not evidence that the fix works. If execution is unsafe, unavailable or unauthorized, use the best permitted evidence and state its limitation.

Use mutation only when it materially tests the claimed guard and is authorized and safe. Check that the intended test was selected, the code ran, the fixture could express the defect, and a failing result failed for the intended reason. Restore only the exact owned change, verify the final bytes and any rebuilt artifact, and preserve unrelated work. Do not mutate a read-only review or bypass a security boundary.

If a test failure may disclose sensitive values and checking that failure is authorized, exercise the actual failing assertion with a synthetic canary and inspect the retained output without revealing the canary. Assertion frameworks can print subexpression values even when the assertion appears boolean; a passing test or inspection of the happy path does not establish failure-output confidentiality.

Counts, searches and output must cover the actual question. Truncation, deselection, collection failure and zero records can make a result appear cleaner than it is. Report the command, relevant scope, outcome and limitations; do not report a partial or still-running check as passed. For noisy command evidence, use [compact command reporting](../compact-command-reporting/SKILL.md); for a final or post-repair validation pass, use [validation evidence](../validation-evidence/SKILL.md).

For examples of misleading mutations and search results, consult [worked instances](instances.md) when applicable.
