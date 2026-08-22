---
name: verified-findings
description: Establish a defect, a fix or a negative by execution rather than argument. Use when reporting a bug, reviewing code, running a mutation to prove a test guards something, closing a finding, or claiming "this is covered" / "this does not leak" / "nothing calls that". Covers the five ways a green mutation lies, why a fix needs its own evidence, and why a truncated or elided result reads as a clean one. Триггеры RU — «докажи что тест ловит», «мутационная проверка», «это точно покрыто», «убедись что не течёт», «проверь находку», «ревью нашло дефект»; EN — mutation testing, prove the test fails, is this covered, verify a finding, confirm a negative, adversarial review.
---

# Verified findings

A hypothesis about a defect is not a finding until a test confirms it, and **the
test must be able to fail**. Everything below is the accumulated cost of
discovering that a result can be truthful and still answer a smaller question
than the one being asked.

## The core rule

Reading the code, tracing the logic and constructing a convincing story produce
a **candidate**. Decisions — fix it, ship it, reject it, design around it — are
made only on candidates a test has turned into facts.

**This cuts both ways.** A hypothesis that a defect does NOT exist also needs the
test. "Unreachable", "nothing clears it", "nobody passes None" are negatives, and
a negative established by reading or by grep is only as good as the search behind
it.

## Before believing a GREEN mutation — five checks

A mutation that leaves the suite green is the most common way a non-result
impersonates a clean one. Confirm all five, in this order:

1. **The test can fail at all.** A test written for a defect that has just been
   fixed is the likeliest of all to be vacuous.
2. **It failed for the REASON intended.** Read the failure output, not the
   summary line. A mutation that raises before reaching the assertion produces a
   red test that proves nothing about the assertion.
3. **The deciding test was SELECTED.** `-k` and `-m` answer "did the selected
   subset pass", which is smaller than "did anything catch this". The
   `deselected` count is printed on every run and nobody reads it.
4. **The code still COMPILED.** A collection or syntax error prints no test count
   at all — which reads like "not caught" if you look at the tail instead of
   noticing that no count appeared.
5. **The fixture can EXPRESS the condition** the test claims to check. A scoping
   test whose fake cannot exhibit cross-scope reuse proves nothing about scoping,
   whatever the code does.

## A fix needs its OWN evidence

A finding is established by a mutation; **a fix is not established by that same
mutation going red.** They are different claims and need different evidence.

- **Drive the finding before building the fix** — even one from a reviewer who
  has been right all day. A review's evidence establishes that the reviewer saw
  something; it does not establish what. A fix built on an unreproduced finding
  is dead code carrying a docstring that claims to work, which is worse than
  absent code because the next reader trusts it.
- **A predicted defect can be real and still be the wrong defect.** The
  prediction is usually right about existence and wrong about the symptom — and
  the fix follows the symptom.
- **Probe a proposed pattern against the real artefact** before adopting it. A
  regex that also matches the page's own content does not get fixed later; it
  gets switched off, and its removal looks like housekeeping.

## Mutation hygiene

- **Substitute, never delete.** A deleted line has no unique anchor to revert
  against. Assert the match count is exactly 1 in both directions.
- **Take a checksum baseline before the round** and verify it after every revert.
  A mutant introduced and reverted between commits is invisible to `git status`.
- **Reverting the tree does not revert the IMAGE.** If the gate builds an image,
  the mutant is baked into it and `up` does not rebuild. Rebuild before trusting
  anything that stand serves.
- **One payload per check.** A payload visible to two checks cannot tell you
  which one fired — and the wrong one firing reads as success.

## A truncated result is indistinguishable from a clean one

- `head`, `tail` and scrollback elide. **Count with `-c`; never read a list and
  report its length.**
- pytest elides long collections with `...`. A grep for a value it replaced
  returns zero and reads as clean.
- Case matters: if the code casefolds before comparing, a case-sensitive search
  finds nothing. **Use `grep -i` on any disclosure check.**
- **A zero-hit search proves nothing until you confirm the instrument works** —
  search the same artefact for something you know is there. A grep for secrets
  in a log that contains no log records at all returns zero for the wrong reason.

## Proving that a failure does not disclose

For any assertion whose failure output could carry a secret: **force the failure
and grep the saved artefact** — the file, not the terminal.

⚠ Reading the assertion is not enough, and neither is a shape sweep. pytest
explains every **sub-expression** with its value, so `assert not missing` prints
the set. Reduce to an int or a bool BEFORE the assert. And the question is not
where an operand comes from in the happy path — it is **what the operands hold
in the state where the assertion fails**, because a safety analysis must not
assume the machinery whose failure the test exists to detect.

## Worked instances

Fifteen real cases, each with the mutation, the wrong conclusion it nearly
produced, and what caught it → [instances.md](instances.md). Read it when a rule
above needs justifying to someone, or when a result looks clean and you want to
know which of the five ways it might be lying.
