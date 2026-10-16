# Living With Legacy — Migration Patterns

How to evolve a system without rewriting it, and without letting the old part rot the new part.

## 1. Parallel versions as sibling namespaces

**Principle**: A new version of a flow lives as a sibling namespace (`Order/` and `Order/V2/`) with its own classes — never as version-ifs scattered through the old code. The old version's code is frozen: bug fixes only, no new features.

**Why**: Interleaved version branches make both versions untestable and unfinishable. Parallel trees keep the old one stable and let the new one be built with current standards.

## 2. Per-entity version routing — zero-migration cutover

**Principle**: Which version handles a given record is decided by a **version tag stored on the record itself** (stamped when first written), not by a global flag or account-level config. Old records stay on the old flow for life; new records start on the new flow. Both coexist indefinitely.

**Why**: No data migration, no big-bang cutover, no window where half-migrated records are visible to the wrong flow. Rollout and rollback become routing decisions.

## 3. The mapping layer as a rename anti-corruption layer

**Principle**: Modern domain vocabulary over a legacy storage schema, with the translation confined to the persistence mapping (`customerId → cust`). The codebase reads clean; the data never migrates.

## 4. Bridge markers with an exit condition

**Principle**: Every temporary bridge to legacy code carries a greppable marker stating the **precondition for its removal** — `@legacy-bridge: replace with X when Y is migrated` — not a date, not a vague TODO. The marker is the backlog.

## 5. "Stop making it worse" beats "rewrite"

**Principle**: The enforceable migration policy is: no new feature code in legacy areas. One rule, adoptable per team, no coordination needed. Enforce with an automated gate (CI check with a size threshold) plus explicitly enumerated exceptions (bug fixes, thin glue delegating to new code, config strings) and an explicit bypass label — a gate without escape hatches gets disabled.

**Measure the debt instead of asserting it**: classify commits by area from git history and compute fix-rate per area (fixes/commits). Legacy areas typically show measurably higher fix rates — put a cost on the delta and the policy funds itself.

## 6. Enumerate every write path

**Principle**: During a strangler migration there are usually **two** write paths (new infra + legacy sync). Document all of them where agents/developers will see it, because tests that exercise only the new path are green and wrong — the feature works in tests and breaks in the legacy-facing surface.

## 7. Modularity is a prerequisite for AI-assisted development

**Principle**: An AI agent can only load less context if boundaries exist. The same change can need 50× more context in a god-class codebase than in a modular one — which translates directly into worse correctness and iteration speed. This is a new, quantifiable argument for paying the boundary cost, on top of the classic ones.
