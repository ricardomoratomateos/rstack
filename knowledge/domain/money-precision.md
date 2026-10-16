# Money & Precision

Extends [value-objects.md](value-objects.md): money is always an `Amount` VO. This document covers how the arithmetic, rounding, and storage behind that VO must work.

## 1. Maximum precision inside, round exactly once

**Principle**: All intermediate arithmetic runs at maximum precision (arbitrary-precision decimal math — bcmath, BigDecimal, decimal.js — with a named constant, e.g. `HIGH_PRECISION_DECIMALS = 14`). Rounding happens **exactly once**, at the boundary where the final value leaves the calculation.

**Why**: Every intermediate rounding injects an error that compounds. One rounding point means one place to audit.

**Anti-patterns**: rounding inside a loop; rounding a subtotal and then using it in further math; float intermediates "because it's just a multiplication".

## 2. Three precisions for three different jobs

**Principle**: These are different concepts — never reuse one for another, each gets its own named constant with a comment stating its job:

| Job | Example | Purpose |
|---|---|---|
| Presentation/storage precision | 2 decimals (per-tenant setting) | what the user sees and the document records |
| Comparison/identity precision | 5 decimals | deciding "is this the same value?" without binary-float ULP drift creating phantom differences |
| Accumulation epsilon | `1e-9` | deciding "is this effectively zero?" after repeated add/subtract cycles |

**Why**: Using presentation precision for comparison creates false equality; using exact equality on accumulated values creates false inequality (`1e-17` residue after add-then-remove).

## 3. Rounding policy is a domain concept

**Principle**: When a calculation can legitimately round in more than one way (per-item then sum, vs sum then round; half-up vs banker's), that choice is a **domain policy** — modeled as a strategy, configurable where the business/regulator requires it — not an implementation detail buried in a helper.

**Why**: The policies produce genuinely different totals, and which one is correct is decided by regulation or agreement, not by code preference.

## 4. Recalculation is not always idempotent

**Principle**: If an external system already reconciled a derived value (totals with rounding adjustments applied at the source), recomputing it locally *destroys* the reconciliation. Mark the points in the flow where recalculation is forbidden, and preserve the received value instead.

**Rule for agents**: before adding a "recalculate on save" step, check whether the value can arrive pre-reconciled from outside.

## 5. Money-safe comparison and hashing

**Principle**: To compare or content-hash structures containing amounts: normalize every amount to the comparison precision (rule 2) and sort object keys, **then** hash/compare. Assert on the string form of the VO in tests, never on floats.

## 6. Storage: strings (or a true decimal type), never binary floats

**Principle**: Amounts are persisted at maximum precision as **strings**, or as the engine's real decimal type (`Decimal128`, `DECIMAL`) — never as a binary float/double. In MongoDB specifically: store the string representation.

**Why**: A double cannot represent most decimal amounts exactly; corruption compounds silently. Real-world evidence: bare floats in an inventory system produced NaN/Infinity values in production that required a dedicated repair tool.

**When legacy storage forces doubles**: the cast lives in exactly one place, at the last infrastructure step (a custom ORM type / final projection stage), documented as a known compromise — never earlier in the flow.
