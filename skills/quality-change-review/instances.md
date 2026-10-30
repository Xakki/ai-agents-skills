# Worked instances

Fifteen real cases from one codebase over three days. Each one produced a result
a careful person would have quoted. They are grouped by which rule they justify.

Format: **what happened** → *the wrong conclusion it nearly produced* → **what
caught it**.

---

## The green mutation that lies

### 1. The reason was wrong, not the result
To prove whether a failing assert would print secrets into a saved log, the
mutation made the lookup call a function the test had monkeypatched to raise. It
re-raised, the test died **before reaching the comparison**, and the grep found
0 secrets. → *"This site does not leak" — with a driven mutation and a clean grep
behind it.* → Reading the failure OUTPUT rather than the summary line: the
failure was the raised error, not the assertion. A second mutation that bypassed
the patch reached the assert, and the log carried the values.

### 2. The deciding test was deselected
A mutation round ran with `-k 'document or vault or origin'`. The test that
catches the mutated branch matched none of those words and sat among the **443
deselected**; the round reported "10 passed". → *"The mutation was not caught."*
→ Re-running against the whole file. The `deselected` count was on screen the
whole time.

### 3. The code never compiled
A payload put double quotes inside a double-quoted literal. The module stopped
parsing, the runner printed `1 error during collection` and **no summary line at
all**. → *"Not caught."* → Noticing that no test count was printed. A collection
error, a syntax error and a green run look alike only from the tail.

### 4. The fixture could not express the condition
A mutation made a scoping predicate a tautology and the test passed. Not because
the predicate held — because the fake's second client carried no state to reuse,
so cross-scope reuse was impossible **in the harness** whatever the code did. →
*"Scoping is enforced."* → Sharing one store between both fakes; the mutant went
red immediately. A test that cannot observe the condition proves nothing about
it.

### 5. The payload was visible to two checks
A leak payload used `cdn.example.com`. One test went red — but it was the
*hostname* check firing because `.com` was in a TLD list, not the *fetch* check
the mutation was aimed at. Swapping to a bare IP made everything pass. → *"The
fetch route is covered."* → One payload per check, chosen so only the target can
see it.

---

## A fix is a separate claim

### 6. The reviewer's fix still leaked
A test compared two sets of secret values; the failure printed both into a saved
log. The agreed fix — `assert not missing and not extra` — **still leaked**,
because the runner explains each sub-expression and the sets are named inside the
asserted expression. → *"Fixed."* → Driving the failure again after the fix and
grepping the artefact. The working shape reduces to `len()` before the assert.

### 7. The fix was built on a finding nobody reproduced
A review reported that redaction covered only a flat key, with nested keys and
in-string values escaping. An implementer wrote a nested walk on the strength of
it. Measurement showed **both were already covered** by the underlying library.
Removing the walk changed nothing. → *"Now it is covered"* — with a docstring
saying the walk did the masking. → Reproducing the finding before building. Dead
code that claims to work is worse than absent code.

### 8. The proposed regex matched the page's own content
A "no hostname on this page" scan was argued to need no allowlist "because the
page starts clean". It matched the page's own link and a CSS selector. → *A check
that fires on legitimate content — which does not get fixed, it gets disabled,
and the removal looks like housekeeping.* → Running the proposed pattern over the
real render before writing it in.

### 9. The predicted defect was real and had the opposite symptom
A race was predicted: writer A silently retires writer B's replacement row.
Driven, the database **refused A's write**, so the real symptom was a job error
after an operation that had already succeeded. → *A fix guarding the row, leaving
the actual failure untouched.* → The fix needed the guard AND the error
swallowed, which only the execution revealed.

---

## Truncation and instruments

### 10. `head` elided the answer
A findings table said "4 occurrences". The count came from `git grep … | head
-10` read as a complete list. The real count was **9 across 3 files**. → Counting
with `-c`.

### 11. The search was case-sensitive and the code casefolds
A canary search with `grep -F "LEAKCANARY"` returned 0 — the code lowercases
before asserting, so the log held `leakcanary…`. → *"Does not leak."* → `grep -i`,
and re-running every earlier search case-insensitively before trusting any of
them.

### 12. Zero hits because nothing was there to find
A probe checked whether media objects leak into logs. The saved artefact showed 0
hits. Grepping the same artefact for **any** log record also returned 0 — logging
was not initialised in that process. → *"Guarded."* → Searching for something
known to be present, to prove the instrument works. The mutation had proved
nothing in either direction.

### 13. Two runs collided on one shared stand
A gate run reported two failures that looked exactly like a real regression.
Another process was holding the same test environment in a deliberately broken
state. → *A second, invented defect.* → Re-running alone. No exit code becomes a
finding until it reproduces on an environment just verified to be free.

---

## Guards that answer the smaller question

### 14. The guard mirrored its subject instead of asking it
A test asserted that no test file sits outside the directories the gate
collects — with the directory list **hardcoded**. Removing a directory from the
build target left the guard green while hundreds of tests were collected by
nothing. Rewritten to parse the build file, it was defeated again by an ordinary
**comment**: the parser matched a line the build tool never runs. → *Twice: "the
layout is guarded."* → Attacking what the guard mirrors, not the guard. The
non-proxy version asks the build tool itself what it would run.

### 15. Reverting the tree did not revert the image
After a mutation round was reverted and verified by checksum, and the whole suite
was green, the running service still served output built from the **mutated**
configuration — every gate target depends on a build step, and bringing the stack
up does not rebuild. → *"Clean."* → Reading the live output. No test could have
caught it: the tree was correct.

---

## The one that is not about tooling

**A verification has a timestamp, and a claim made from it inherits that
timestamp.** "The line is still there" proves only that the file still has that
many lines. Re-read before asserting that something is missing — three separate
false reports in one session came from acting on a reading taken minutes earlier,
against a tree that had moved.
