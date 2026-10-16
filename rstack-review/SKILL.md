---
name: rstack-review
description: Review a PR against Ricardo's engineering principles (ricardo-knowledge repo) AND against every ADR of the current project. Use whenever the user asks to review a PR, pastes a PR URL/number, or says "review this PR", "run the review", "pr-review". Always re-reads the knowledge docs and ADRs at invocation time — they change frequently, never rely on remembered content.
---

# PR Review against ricardo-knowledge and the project's ADRs

Review a PR using **two sets** as criteria: the documents under `~/Projects/rstack/knowledge` and ALL of the current project's ADRs. Both are read in full, always, with no filtering by whether they "sound relevant" to the PR — a date-handling PR doesn't always say "date" in the title, and an ADR that looks unrelated is exactly the one that slips through.

**Hard rule**: no filtering by topic. Neither ricardo-knowledge nor the ADRs get selected by perceived relevance — they are all read, in full, one by one. The cost of reading too much is always smaller than the cost of an incomplete review.

## Step 1 — Enumerate and read ALL of ricardo-knowledge (mandatory, always, no exception)

1. `find ~/Projects/rstack/knowledge -iname "*.md"` — count the real total number of documents. Don't trust the `README.md` index alone: it can be stale.
2. Read every one of those documents **in full**. There's no "whichever applies" shortcut — it's the complete set.
3. Keep the count (N) for the Step 5 output.

## Step 2 — Enumerate and read ALL of the project's ADRs (mandatory, always, no exception)

1. Look for the current repo's ADRs, trying the usual conventions — `find . -path "*/.ai/ADR/*.md"`, `docs/adr/`, `doc/adr/`, `adr/` — and whatever the repo's own CLAUDE.md/`.context-hints`/README points to if it uses a different one. Count the real total (M).
2. Read every ADR **in full**, one by one — same as Step 1, with no filtering by whether the title "sounds" related to the PR. (Real example: a timezone/date-handling ADR doesn't have to be mentioned in the title of a PR touching recurring dates, due dates, or cron jobs — and that's exactly the kind that gets violated most by being skipped.)
3. Keep the count (M) for the Step 5 output.

## Step 3 — Get the PR diff

- If the user gave a URL or number: `gh pr view <ref>` and `gh pr diff <ref>`.
- If no reference was given: the current branch's PR (`gh pr view --json number,title,url` in the current repo); if there's no PR, use the branch's diff against the base (`git diff main...HEAD`).
- Also read the PR description and the full files the diff touches when the diff's context isn't enough to judge.

## Step 4 — Review

Evaluate the diff against **both** sets you read (ricardo-knowledge + the project's ADRs). For each finding:

- Cite the exact source and the specific rule being violated (e.g. "async-workers.md rule 7 — idempotent jobs", or "ADR-007-derived-values — derived values must be computed on demand, not persisted").
- Point to file and line (`path/file.ts:123`).
- Distinguish severity: **blocking** (violates a hard rule / explicit anti-pattern, or contradicts an ADR), **improvement** (a preferred pattern is documented), **note** (minor observation).
- Also acknowledge what the PR does well with respect to the principles — briefly.

Don't invent rules that aren't in the documents: if something looks wrong to you but no document/ADR covers it, label it "opinion, not covered by ricardo-knowledge or any ADR" and suggest whether it's worth documenting.

## Step 5 — Output

Short, plain format (Ricardo prefers concise answers):

1. First line: coverage count, e.g. "ricardo-knowledge: 24/24 reviewed · ADRs: 7/7 reviewed" — so it's visible that no sampling happened.
2. One-line verdict (approve / changes needed).
3. List of findings ordered by severity, each in 1-2 lines with its citation (document or ADR).
4. If any finding revealed a gap in ricardo-knowledge or in the ADRs, a final line suggesting the doc/rule to add.

Don't publish the review on GitHub unless the user explicitly asks for it.

## Step 6 — Explain the domain in plain terms (always, right after the verdict)

Ricardo often reviews PRs he didn't write, for features he has no prior knowledge of. A list of findings tells him "what's wrong" but not "what this is." So, after the verdict and the findings, always add a second part explaining the model in plain terms — no need to be asked.

Cover, to the extent the PR has it:

1. **The aggregate / root entity**: which object is the entry point, how it references the new thing (field, type, nullable/embed), and why consistency lives where it lives.
2. **The VO/entity tree**: sketch the nested structure (even as indented text) and, for each field, one sentence on **what it's for in business terms** — not just its type. If a name doesn't reveal its purpose, say so explicitly.
3. **Commands/queries**: which use cases it exposes, the standard flow of each handler (load → delegate to the domain → persist → side effects), and what each one does differently (e.g. idempotency guards).
4. **Domain events**: what gets emitted, with what content, and what they'd be useful for to a future consumer.
5. **End-to-end flow of one concrete case**: pick a representative command and trace the full call, step by step, from the Command down to persistence.
6. **Is it scaffolding?** — actively check whether the PR has real consumers: `git grep` the new feature's name, excluding the new files themselves and the tests. If nothing else in the repo calls the new commands/queries, say so explicitly ("no consumer yet, this is the groundwork for a future flow") instead of leaving Ricardo to infer it on his own. If a previous module with a similar name exists, point out the difference so they don't get confused.

Format: normal technical prose (not the short list from Step 5), with file:line citations where helpful. This part can be longer than the verdict — the goal here is for Ricardo to understand the "what" and the "why," not brevity.
