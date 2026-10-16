# Architecture & Completeness Tests

Rules that live only in a review checklist die. Rules encoded as tests that break the build stay true forever.

## 1. Architecture rules are executable

**Principle**: Structural rules — "domain never imports infrastructure", "every controller checks permissions", "commands return void" — are enforced by tests/static-analysis rules that fail the build, not by code review.

**How I apply it**: dependency-rule tests (PHPat, ArchUnit, dependency-cruiser…), or custom tests that reflect over the codebase and assert the rule.

## 2. Exceptions are scoped, never blanket

**Principle**: When a class must legitimately break a rule, don't exclude it from the test — add a second assertion that narrows the exception to exactly what it needs ("this class may depend on exactly this one forbidden class and nothing else").

## 3. Completeness tests — fail when someone forgets something

**Principle**: When a change in place A requires a matching change in place B (new translation key → all locales; new enum case → its handler; new endpoint → its docs entry; duplicated map → its mirror), write a test that **enumerates the source of truth and asserts every item has its counterpart**. Forgetting becomes a red build, not a production surprise.

**Examples**:
- A test that fails if a documented key lacks its translation.
- A registry that walks all implementations of an interface and asserts each is registered/configured.
- Two maps that must stay in sync, pinned by a test comparing them.

**Rule for agents**: when you notice a "remember to also update X" situation, propose the completeness test in the same PR.

## 4. Incident → permanent architecture test

**Principle**: When a production incident has a *structural* cause (a class of code that is dangerous, not a one-off logic bug), the fix ships with a test that scans the whole codebase for that shape and fails on any new occurrence — with the incident ID in the docblock.

**Canonical example**: ORMs hydrate via `newInstanceWithoutConstructor()`, so constructor-parameter defaults never run on records stored before the field existed → "uninitialized property" crashes. The permanent test walks all mappings and asserts every nullable mapped property has a class-body default.

**Meta-rule**: constructor-based unit tests structurally *cannot* catch schema-evolution bugs — they always run the constructor. Hydration-shape bugs need tests that load legacy-shaped data.

## 5. Burn-down baseline for adopting rules on existing code

**Principle**: A new rule on an old codebase starts with a baseline file of pre-existing violations. The build fails on any violation **not** in the baseline, and the baseline may only shrink. Never add an entry to make a new test pass.

## 6. Global-state isolation

**Principle**: With shared test processes, a leaked global (frozen clock, timezone, static cache) makes an unrelated test fail later — **the failing test is the victim, not the polluter**.

- Cleanup must survive a throw: release global state in `tearDown`/`finally`, never inline at the end of the test body.
- Neutralize everything, but only *gate* on leaks that are genuine bugs (don't blame well-behaved tests for state that normal code mutates).
- The CI gate enumerates **all** offenders in a separate step — aborting at the first one hides the rest.

## 7. Never destructive cleanup against shared databases

**Principle**: Tests never run broad deletes (`deleteMany({})`, `truncate`) — when the environment shares a real database, one unfiltered `tearDown` destroys real data (it has happened). Isolation comes from unique per-run identifiers and querying only what you created; destructive cleanup is acceptable only in disposable environments (throwaway containers).
