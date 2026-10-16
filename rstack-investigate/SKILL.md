---
name: rstack-investigate
description: Systematic root-cause debugging with hard gates against guessing. Use when asked to debug, investigate a bug, find why something fails, or before proposing any fix for a reported defect — especially from a bug report (Slack, Jira, user complaint) rather than a stack trace already in hand. Do NOT use for a simple typo/one-line fix the user already diagnosed themselves.
---

# rstack-investigate

## Iron Law

**DO NOT PROPOSE A ROOT CAUSE OR WRITE ANY FIX WITHOUT HAVING REPRODUCED THE BUG WITH REAL DATA.**

Reading code and reasoning about what "should" happen is not evidence. A hypothesis without confirmed reproduction is called a hypothesis — never "the cause," not in your own head and not in what you tell the user.

This rule exists because it was broken twice in the session that gave rise to this skill: a root cause was proposed (invented business rules) without checking the account's real data, and then a whole fix (`RulesRepository`) was built from code reading alone, which turned out to be useless in production because the data it depended on (`CountryRules`) didn't exist for that account. Both times the user had to stop the model with real data it hadn't asked for.

---

## Phase 1 — Root Cause Investigation

1. **Symptoms**: read the report as given (Slack, ticket, log) without reinterpreting it. If a needed piece of data is missing (account ID, order, hook), ask for it — don't invent it or assume "it's probably X".
2. **Trace the code**: from the symptom backwards. Before assuming two similar-looking functions/queries are interchangeable, read their call sites — the difference is usually in a caller's guard, scope, or transaction, not in the function itself.
3. **`git log --oneline -20 -- <affected files>`**: is this a regression? What changed, and when? If a recent PR/commit touches the same area, read it before continuing.
4. **Reproduce with REAL data, never invented — and do it as an automated test in the repo itself, not as a separate script.** If the project has a test suite (acceptance/integration/unit), the reproduction IS that test: build it now, with the real payload/data (production logs, DB), and run the suite to watch it fail (RED). Do not first write a throwaway script or REPL session "to understand," and only later — once you already have the root cause — write a separate test. It is the same artifact from the start. That test is what you'll use in Phase 3 to test each hypothesis, and it's what will end up being the regression test of Phase 4 — there are not two tests, there's one that goes from RED to GREEN. If the repo has no usable test infrastructure for this case, a script is your only option — say so explicitly, because then you won't have a real regression test in Phase 4 and that gap needs to be compensated some other way. If you can't reproduce it either as a test or as a script, go back to step 1 and gather more evidence; do not move to Phase 3 without reproduction.
   **Prefer integration/acceptance level over unit-with-mocks.** If the project has both, pick the one that exercises the real dependency the bug lives in (real DB, real repositories) over a unit test that fakes/mocks that exact dependency — a mocked unit test can make a wrong fix look correct, which is exactly what almost shipped with `RulesRepository`: a unit test mocking the repository would have passed even though the real dependency (`CountryRules`) was empty in production. Only fall back to a unit test with mocks if the bug is genuinely inside pure logic with no external dependency involved.
5. Check whether similar investigations/fixes already happened in the same area (`git log`, project memory/ADRs). A recurring bug in the same spot is an architectural smell, not a coincidence.

**Output of this phase**: a concrete, falsifiable root-cause hypothesis — not a vague "looks like a concurrency issue."

**Checkpoint — STOP.** Report this phase's output (the hypothesis + the evidence gathered) and ask the user explicitly whether to proceed to Phase 2. Do not continue on your own judgment that it's "obviously fine to keep going."

---

## Phase 2 — Pattern Analysis

- Compare against bugs already fixed in this repo (prior session memory, CHANGELOG, commits with a similar message). If a similar fix is already documented, your hypothesis must explain why this case is different, not assume it's the same bug again.
- Generic patterns to explicitly rule out: race condition, null/nil propagation, partial state corruption (half-finished transactions), external integration failure, configuration drift between environments, stale cache.
- If nothing fits, move to Phase 3 with your best hypothesis — don't invent a pattern just to force a fit.

**Checkpoint — STOP.** Report which pattern (if any) applies and ask the user explicitly whether to proceed to Phase 3.

---

## Phase 3 — Hypothesis Testing

**STOP. Do not write any fix yet.**

1. Add temporary instrumentation (`fwrite(STDERR, ...)`, `error_log`, or the language's equivalent) at exactly the suspected point — not one level up or down.
2. Run the SAME test from Phase 1 (real data, in RED) and read the output line by line — not a different script/repro "while you're at it"; if you need another case, it's a variation of the same test, not a new tool.
3. Does the evidence confirm the exact hypothesis, or just something similar? If it's "something similar," don't call it confirmed — go back to step 1.
4. **3-strike rule**: if 3 hypotheses fail in a row, stop. Ask the user instead of continuing to guess — it may be an architectural problem, not a wrong hypothesis.
5. **Revert ALL temporary instrumentation before moving to Phase 4** (`git checkout -- <those files>`, confirming with `git status` that nothing is left behind). Never leave debug `fwrite`/`error_log` calls in production code.

**Red flags — stop if you see any of these:**
- "Quick fix for now" — there is no "for now," fix it properly or escalate.
- Proposing a fix before having traced the full data flow — you're guessing.
- Trusting a subagent's (or your own) code reading without verifying it against the real case — a piece that "in theory" fits can depend on data that doesn't exist in production (this happened with `RulesRepository`: it depended on `CountryRules` rules that no longer existed for the real account).
- Doing a find-and-replace or sed over a shared file to isolate an experiment, without scoping it to your exact block — check `git diff --stat` after any bulk edit: if it touches more lines/tests than expected, revert and redo it scoped.

**Checkpoint — STOP.** Report the confirmed root cause with its evidence (the RED test output, instrumented) and ask the user explicitly whether to proceed to Phase 4. Do not start implementing while waiting for the answer.

---

## Phase 4 — Implementation

Only with a confirmed root cause (Phase 3 with evidence, not suspicion).

1. **Minimal fix**: the smallest change that eliminates the real cause. No adjacent refactors.
2. **Does the 3-subagent adversarial pattern apply?** Only if one of these conditions holds — otherwise implement it yourself directly:
   - The fix touches a function/class shared by more than one caller.
   - Your first fix attempt broke an existing test.
   - The root cause involves a non-trivial piece of the domain (more than one layer, or an interaction between modules).
   If it applies: launch 3 agents in parallel (a mix of models — e.g. 2 fable + 1 opus) with the full context of the bug (confirmed root cause + Phase 3 evidence + what you tried and why it failed), asking each for one concrete recommendation (not a menu of options) with an exact file/method. Compare the three, verify their claims against the code and the real data yourself before applying anything — a subagent can be just as confident and just as wrong as you.
3. **The regression test is the same test from Phases 1 and 3** (the one already RED with real data) — do not write a new one. Apply the fix and confirm THAT test turns GREEN. If at any point you wrote a different test for this, you drifted from the flow — go back and use the same one.
4. Run the full affected suite. Paste the output — don't say "it should pass," prove it.
5. If the fix touches more than 5 files, ask the user before continuing (large scope for a bugfix).

**Checkpoint — STOP.** Report the fix (file:line), why it's minimal, and the full-suite result, and ask the user explicitly whether to proceed to Phase 5.

---

## Phase 5 — Verification & Report

1. Reproduce the original bug from scratch (same case as Phase 1) and confirm it no longer happens. This is not optional.
2. Structured report:
   ```
   Symptom:          [what the user reported]
   Root cause:       [what was actually wrong, confirmed with evidence]
   Fix:              [what changed, with file:line]
   Evidence:         [test/reproduction output before and after]
   Regression test:  [file:line]
   Status:           DONE | DONE_WITH_CONCERNS | BLOCKED
   ```

**Checkpoint — STOP.** Present the report and ask the user explicitly whether to proceed to Phase 6.

---

## Phase 6 — Additional coverage

During the investigation (especially if subagents were used in Phase 4), related surfaces may turn up that aren't the reported bug but smell similar. Don't dismiss them by ear, and don't add tests for them by ear either:

1. Verify each one against the real code (does the data it would need to fail actually exist in this case, or in some plausible case?).
2. If it has confirmed real impact → add a regression test for it too, in Phase 4.
3. If it has no real impact (you checked and it doesn't apply) → say so explicitly in the Phase 5 report, with the reason, instead of silently dropping it.

**Checkpoint — STOP.** Report what you checked and what you added (if anything), and ask the user explicitly whether to proceed to Phase 7.

---

## Phase 7 — Audit against ADRs and ricardo-knowledge (mandatory, no exceptions)

This phase is not optional, nor proportional to the size of the fix — it's as non-negotiable as the Iron Law. Do not do it yourself inline: delegate it to a fresh subagent (with none of your prior context), model `sonnet`, with exactly this task and nothing else:

> Given this diff/fix: [paste diff or description + touched files]
>
> 1. Enumerate with `find`/`ls` ALL ADR files in the repo (look under `.ai/ADR/`, `docs/adr/`, `.context-hints`, or wherever the project's CLAUDE.md points). Count the total.
> 2. Enumerate ALL documents under `~/Projects/rstack/knowledge` (use its `README.md` as an index, but verify with `find` that the index isn't stale). Count the total.
> 3. Read every one of both sets **in full, one by one** — do not sample, do not read only "the ones that sound relevant by title."
> 4. For each one, state explicitly whether the proposed fix complies with it, contradicts it, or doesn't apply.
> 5. Report with an explicit count: "N/N ADRs reviewed, M/M ricardo-knowledge docs reviewed" + a list of any conflicts found, with an exact citation (document + rule).

Why a fresh subagent and not you: a model already loaded with context and eager to close out the task tends to turn "review" into "read what sounds relevant and skip the rest" — the explicit N/N count in a narrow, fresh task is what makes this verifiable instead of a promise.

If the subagent reports a blocking conflict, go back to Phase 4 before considering the fix closed.

**Checkpoint — STOP.** Present the audit's N/N and M/M counts plus any conflicts, and ask the user explicitly before declaring the investigation closed.

---

## General rules

- Stop at the end of every phase and ask the user before moving to the next one — not just at the 3-strike rule or the >5-files gate. This is a stop-and-confirm workflow, not an autonomous end-to-end run.
- Never apply a fix you cannot verify by reproducing the original bug.
- Never say "this should fix it" — prove it with the test and the reproduction.
- 3+ failed fix attempts → stop and question the architecture; don't be the one insisting the next hypothesis will work.
- If you used real production data (account, order, payload) in a new test, say so explicitly in the report — don't disguise it as synthetic, or the other way around.
