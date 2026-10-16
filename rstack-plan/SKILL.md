---
name: rstack-plan
description: Propose-and-wait planning for new features. Use before starting any non-trivial feature work — when the user describes something to build, not a bug to fix (for bugs, use rstack-investigate instead). Produces a negotiated, approved plan with incremental diagrams; does not implement anything itself.
---

# rstack-plan

## Iron Law

**NEVER ACT ON ASSUMPTION. PROPOSE OR LISTEN — NEVER JUST DO.**

This skill exists because of a very concrete failure: asked to think through a new skill together, the model instead jumped straight to producing a finished diagram of its own design, without first confirming it had understood the request. The fix wasn't "think harder" — it was a structure that makes jumping ahead impossible: understanding gets confirmed before anything else happens, and the plan gets built question by question with the user, not delivered as a finished monologue.

This skill's job ends at an approved plan. It never writes implementation code itself — what happens after approval is separate, ordinary work (or `rstack-investigate`, if what gets approved is a bugfix).

---

## Phase 1 — Listen

Restate the request in your own words, with zero added scope. Do not search the codebase yet. Do not call Edit, Write, or any diagramming tool yet. If the request is ambiguous, say what's ambiguous — don't resolve the ambiguity yourself by guessing the "obvious" interpretation.

**Checkpoint — STOP.** Present the restatement. Wait for explicit confirmation that you understood correctly. "Yes" is confirmation; a correction is not a soft nudge to adjust on the fly — it means go back to Phase 1 and restate again from scratch.

---

## Phase 2 — Survey (read-only, reuse-focused)

The question this phase answers is not "how is something similar built here" in the abstract — it's specifically: **can something that already exists be used as-is, instead of building something new?**

Concrete example: asked to build a new kind of plugin, the right output of this phase is "there's already a working OAuth flow built for plugin auth — reuse it" — not a generic survey of how auth patterns look in this codebase.

1. Search the codebase for existing modules, services, or utilities that solve the same or an adjacent problem.
2. For each one found, state explicitly: reusable as-is / reusable with modification / not reusable (and why).
3. No Edit, no Write — this phase only reads.

**Checkpoint — STOP.** Report what you found (reusable pieces first, patterns second) and ask the user explicitly whether to proceed to Phase 3, or to redirect the approach now that this exists.

---

## Phase 3 — Propose (negotiated, not delivered)

**Do not write a complete plan document and hand it over.** Ask questions one at a time about what Phase 2 left open, and build the plan together with the user's answers. A plan assembled from a single monologue is a decision made alone with a rubber-stamp request attached — that's exactly what this skill exists to prevent.

**Diagrams, when the feature has a flow or multiple actors:**

1. Before attempting any diagram, check whether `archify` appears in your current available-skills listing. Never assume it by checking a hardcoded filesystem path — availability is determined by whether it's listed, because install location varies by machine.
   - Available → use it for both diagram types that apply:
     - a **workflow** diagram, if the feature has branching logic, phases, or gates.
     - a **sequence** diagram, if the feature involves multiple actors/components calling each other over time.
   - Not available → say so explicitly in the proposal and continue with text only. Do not fake a diagram in ASCII as a substitute.
2. **Build incrementally, not once at the end.** As each piece of the plan gets decided through the question-and-answer exchange, update the diagram and show it — republish the same artifact, don't create a new one each time. The user watches it take shape and can correct it mid-build, not only review a finished version.
3. A trivial feature (no flow, single actor, e.g. a config value or a single field) gets no diagram — don't force one.

Keep negotiating — one question, one answer, one diagram update — until nothing about the plan is still open.

---

## Phase 4 — Approval Gate

Present the closed plan: the written decisions from Phase 3, plus the final diagram(s) if any, together as one thing to review — not the text now and the diagram later.

**Checkpoint — STOP.** Wait for an explicit answer. There are exactly two valid outcomes here, and a vague "ok," a thumbs-up emoji, or changing the subject is neither of them — re-ask if the reply doesn't clearly land on one:

- **"This plan is enough"** → done. The plan stands as the deliverable; nothing gets implemented as part of this skill.
- **"Yes, implement it"** → done with this skill; implementation proceeds as separate, ordinary work from here (or via `rstack-investigate` if what was approved is a bugfix, not a feature).

If the user redirects or only partially approves, go back to Phase 3 with the correction — don't patch the plan unilaterally and re-present it as if it were already agreed.

---

## Red flags — stop if you see any of these

- Writing the full plan before asking a single question — that's a monologue, not a negotiation.
- Generating a diagram "to show progress" before the user has actually decided the piece it depicts.
- Treating "ok" or silence as either approval outcome in Phase 4 — neither counts.
- Searching for existing code only after proposing a new design, instead of before — reuse has to come first or it never actually gets considered.
- Jumping to Phase 3 or further because the request "seems simple enough" — Phase 1's confirmation gate has no size exception.

---

## General rules

- This skill never calls Edit or Write against the target codebase — only against its own diagram candidate files. Implementation is explicitly out of scope.
- If `archify` isn't listed as available, don't block the plan on it — note the gap and continue with text.
- Every question asked in Phase 3 should be answerable in one reply — don't bundle three decisions into one question because it's faster.
