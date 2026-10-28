---
name: rstack-plan
description: Propose-and-wait planning for new features. Use before starting any non-trivial feature work — when the user describes something to build, not a bug to fix (for bugs, use rstack-investigate instead). Produces a negotiated, approved plan with incremental diagrams; does not implement anything itself.
---

# rstack-plan

## Iron Law

**NEVER ACT ON ASSUMPTION. PROPOSE OR LISTEN — NEVER JUST DO.**

This skill exists because of a very concrete failure: asked to think through a new skill together, the model instead jumped straight to producing a finished diagram of its own design, without first confirming it had understood the request. The fix wasn't "think harder" — it was a structure that makes jumping ahead impossible: understanding gets confirmed before anything else happens, and the plan gets built question by question with the user, not delivered as a finished monologue.

This skill's job ends at an approved plan, persisted in the brain. It never writes implementation code itself — what happens after approval is separate, ordinary work (or `rstack-investigate`, if what gets approved is a bugfix).

**The plan doesn't wait for the end to exist as a file.** `$BRAIN/<project-folder>/<feature-slug>/spec.md` and `.../plan.md` (see "Locating the brain" in Phase 2) are written and updated progressively, phase by phase — never produced in one shot once everything is already decided. A file that only gets written after the fact is just the chat transcript with extra steps.

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
3. No Edit, no Write against the target codebase — this phase only reads.

**Checkpoint — STOP.** Report what you found (reusable pieces first, patterns second) and ask the user explicitly whether to proceed to Phase 3, or to redirect the approach now that this exists.

### Locating the brain

Every spec and plan lives in the brain, never in the target repo. The brain is `brain/`, a sibling folder of this repo (next to `knowledge/`), gitignored there on purpose — it survives a deleted or orphaned worktree, because it never lived inside one.

1. Resolve its absolute path once, the same way as `KNOWLEDGE` (see Phase 3): `BRAIN="$(cd -P "<this skill's base directory>/.." && pwd -P)/brain"`.
2. Create it if missing (`mkdir -p "$BRAIN"`) — this is local, personal storage, not something to ask the user about.
3. Every ticket gets its own `$BRAIN/<project-folder>/<feature-slug>/`, where `<project-folder>` is the basename of the target repo's root (`git rev-parse --show-toplevel`) — so specs from different projects never collide.

**Once Phase 1 and this phase are both confirmed**, write `$BRAIN/<project-folder>/<feature-slug>/spec.md` (WHAT and WHY — not HOW): the restated request from Phase 1 and the reuse findings from this phase. Use a short kebab-case slug from the feature name agreed in Phase 1 — don't ask the user to name it unless it's genuinely ambiguous. This is the spec, not the plan; it doesn't contain implementation decisions, because none exist yet.

---

## Phase 3 — Propose (negotiated, not delivered)

### Locating the knowledge base

The knowledge base is the `knowledge/` folder of this repo, next to the skill folders. Resolve its absolute path once, before anything else, and call it `KNOWLEDGE`:

1. If the environment variable `RSTACK_KNOWLEDGE` is set, use it.
2. Otherwise resolve it from this skill's base directory (the harness prints it when the skill loads), following symlinks: `KNOWLEDGE="$(cd -P "<this skill's base directory>/.." && pwd -P)/knowledge"`.
3. If that folder does not exist, STOP and ask the user where `knowledge/` is. Do not continue without it, and do not substitute another set of documents.

**Before the first proposal, read ALL of `KNOWLEDGE` in full — mandatory, always, no exception, same hard rule as `rstack-review` Step 1.** `find "$KNOWLEDGE" -iname "*.md"`, read every document, no filtering by whether it "sounds relevant" to this feature — a design that looks like pure CRUD is exactly the kind that quietly crosses a bounded-context or hexagonal-architecture rule without tripping any obvious keyword. Do this once per planning session, right before Phase 3 starts (not once per question, not re-read on every iteration). This exists because proposing a design, getting corrected against a principle already written down in that knowledge base, and re-proposing has happened repeatedly — reading first is what actually prevents the loop, not promising to remember next time.

If the feature also has project-specific ADRs (same discovery convention as `rstack-review` Step 2: `.ai/ADR/`, `docs/adr/`, or whatever the repo's own CLAUDE.md points to), read all of those too, in full, before Phase 3's first proposal.

**Do not write a complete plan document and hand it over.** Ask questions one at a time about what Phase 2 left open, and build the plan together with the user's answers. A plan assembled from a single monologue is a decision made alone with a rubber-stamp request attached — that's exactly what this skill exists to prevent.

**`$BRAIN/<project-folder>/<feature-slug>/plan.md` grows with the conversation, not after it.** After each question gets an answer, append or update the corresponding section of `plan.md` immediately — don't hold the decisions in your head until the end and write the file in one pass once everything is settled. The file at any point in the middle of Phase 3 should be an honest reflection of what's decided so far, including sections still marked open.

**Diagrams, when the feature has a flow or multiple actors:**

1. Before attempting any diagram, check whether `archify` appears in your current available-skills listing. Never assume it by checking a hardcoded filesystem path — availability is determined by whether it's listed, because install location varies by machine.
   - Available → use it for both diagram types that apply:
     - a **workflow** diagram, if the feature has branching logic, phases, or gates.
     - a **sequence** diagram, if the feature involves multiple actors/components calling each other over time.
   - Not available → say so explicitly in `plan.md` and continue with text only. Do not fake a diagram in ASCII as a substitute.
2. **Build incrementally, not once at the end.** As each piece of the plan gets decided, update the diagram and show it — republish the same artifact, don't create a new one each time. The user watches it take shape and can correct it mid-build. Link the artifact URL from `plan.md` as soon as it exists, and keep the link current as the diagram is revised.
3. A trivial feature (no flow, single actor, e.g. a config value or a single field) gets no diagram — don't force one.

Keep negotiating — one question, one answer, one `plan.md` update, one diagram update — until nothing about the plan is still open.

---

## Phase 4 — Approval Gate

Present the closed plan: `plan.md` as it now stands (already up to date from Phase 3's incremental updates — this step does not write it for the first time), together with its diagram(s) if any.

**Checkpoint — STOP.** Wait for an explicit answer. There are exactly two valid outcomes here, and a vague "ok," a thumbs-up emoji, or changing the subject is neither of them — re-ask if the reply doesn't clearly land on one:

- **"This plan is enough"** → done. `spec.md` and `plan.md` stand as the deliverable; nothing gets implemented as part of this skill.
- **"Yes, implement it"** → done with this skill; implementation proceeds as separate, ordinary work from here (or via `rstack-investigate` if what was approved is a bugfix, not a feature).

If the user redirects or only partially approves, go back to Phase 3 with the correction — update `plan.md` to reflect it, don't patch the plan unilaterally in your head and re-present it as if it were already agreed.

Either way, tell the user the file paths once this gate closes. They live in the brain, gitignored by design — there's nothing to stage or commit.

---

## Red flags — stop if you see any of these

- Writing the full plan before asking a single question — that's a monologue, not a negotiation.
- Generating a diagram "to show progress" before the user has actually decided the piece it depicts.
- Treating "ok" or silence as either approval outcome in Phase 4 — neither counts.
- Searching for existing code only after proposing a new design, instead of before — reuse has to come first or it never actually gets considered.
- Jumping to Phase 3 or further because the request "seems simple enough" — Phase 1's confirmation gate has no size exception.
- Proposing a design in Phase 3 before reading all of `KNOWLEDGE` (and the project's ADRs, if any) — a proposal that gets corrected against a principle you could have read first is the exact failure this step exists to prevent.
- Holding decisions in memory and writing `spec.md`/`plan.md` in one pass at the end — the whole point is that the file tracks the conversation, not the other way around.

---

## General rules

- This skill writes exactly three kinds of files, all under `$BRAIN/<project-folder>/<feature-slug>/`: `spec.md`, `plan.md`, and its own diagram candidate files — never inside the target repo, and never touching application/source code there.
- Don't default to `data-model.md`, `contracts/`, `research.md`, or `tasks.md` just because the broader spec-kit convention has them — only add one if this specific feature genuinely needs it, and say why.
- If `archify` isn't listed as available, don't block the plan on it — note the gap and continue with text.
- Every question asked in Phase 3 should be answerable in one reply — don't bundle three decisions into one question because it's faster.
