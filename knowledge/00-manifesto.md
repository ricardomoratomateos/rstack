# Manifesto — Cross-Cutting Principles

These rules apply to **every** project and override any framework convention or "best practice" that conflicts with them.

## 1. KISS — the simplest solution that works wins

**Principle**: Given two valid designs, choose the one with fewer moving parts. Simplicity is a feature, not a compromise.

**Why**: Every layer, abstraction, and indirection has a permanent reading cost. Code is read hundreds of times and written once.

**How I apply it**:
- Start with the direct implementation. Add structure only when the code itself demands it (duplication appears, a symptom from [design-patterns.md](design-patterns.md) shows up).
- Prefer a function over a class, a class over a hierarchy, a module over a package.

**Anti-patterns**:
- Introducing factories, generics, or extra layers "for flexibility" that no current requirement asks for.
- "Elegant" pattern showcases. A pattern must be justified by a concrete symptom it removes.

## 2. YAGNI — do not build for hypothetical futures

**Principle**: Implement what today's requirement needs. Nothing speculative: no config options without a consumer, no abstractions with a single implementation created "just in case".

**Why**: Speculative code is usually wrong about the future AND has to be maintained until then.

**How I apply it**:
- An interface/port is justified by the architecture (see [hexagonal.md](architecture/hexagonal.md)) or by a second real implementation — not by "we might need to swap it".
- Infrastructure choices scale with real needs: in-process event bus before a message broker, a cron before a scheduler platform.

**Anti-patterns**:
- Feature flags, plugin systems, or multi-tenant hooks for tenants that don't exist.
- Parameterizing behavior that has exactly one caller with one set of arguments.

## 3. Explicit > implicit

**Principle**: Code states its intention. Names say what things are in business terms; behavior is visible where it happens.

**Why**: Implicit magic (framework auto-wiring beyond DI, hidden side effects, convention-over-configuration surprises) makes code unreadable outside the head of its author.

**How I apply it**:
- Intention-revealing names: `SettleInvoiceCommandHandler`, not `InvoiceService.process()`.
- Side effects flow through visible mechanisms (events, explicitly injected ports), never hidden in getters or constructors.

**Anti-patterns**:
- Generic names: `Manager`, `Helper`, `Util`, `Data`, `process`, `handle` (without an object).
- Boolean parameters that change behavior (`save(true)`) — use two named methods or an explicit enum/VO.

## 4. Bounded boy-scout rule

**Principle**: Improve what you touch, within the scope of what you touch. No unsolicited mass refactors.

**Why**: Drive-by refactors bloat diffs, hide the real change, and break things nobody asked to risk.

**How I apply it**:
- Fixing a bug in a function → OK to clean that function.
- Fixing a bug in a function → NOT OK to rename 40 files or restructure the module.
- If a large refactor seems necessary, propose it separately; don't bundle it.

## 5. Functional composition over imperative loops

**Principle**: For transformations over collections, reach for `map` / `filter` / `reduce` / `find` / `some` / `every` chains before a `for` or `while`. A loop is justified only when a chain genuinely cannot express it (early-exit on side-effecting I/O with structured error handling, streaming generators, accumulators shared across iterations with real reasons).

**Why**: A chain states WHAT the code does (`open.map(toSummary)`); a loop states HOW (`const out = []; for (...) out.push(...)`). Chains compose, eliminate the mutable loop-variable that breeds off-by-ones, push nested `if` logic into flat pipelines, and read top-to-bottom instead of inside-out.

**How I apply it**:
```ts
// BAD — building an array in a loop
const summaries = [];
for (const order of orders) {
  if (order.isOpen()) summaries.push(toSummary(order));
}

// GOOD — declarative, one expression, no accumulator
const summaries = orders.filter(isOpen).map(toSummary);
```
- `map` for transforms, `filter` for selection, `reduce` for folds, `find` for first match, `some` / `every` for boolean predicates, `flatMap` for nested iteration, `groupBy` / `partition` for bucketing.
- Name intermediate steps when the chain gets long: `const open = orders.filter(isOpen); const summaries = open.map(toSummary);` — readability beats density.
- Side-effecting work that needs structured error handling or early-exit (write to DB with rollback, emit events in order, abort on first failure) is a real reason for a `for...of` or an explicit iterator. Pick the clearer form, then name it.

**Anti-patterns**:
- `for` with `.push()` to build an array (`map`).
- `for` returning the first match / `null` (`find`).
- `for` checking existence (`some`, `includes`, `Set.has`).
- Chained 15-stage pipeline that nobody can read — split it, name the steps, or push it into a method on a collection VO ([value-objects.md](domain/value-objects.md) rule 5).
- Forcing a side-effecting sequence through `forEach` chains so it "looks functional". Side effects want explicit iteration, not contrived pipelines.

## 6. Rules for AI agents working with me

- Communicate with Ricardo in clear, simplified technical Spanish (Castilian). Use short sentences, active voice, one idea per sentence, and consistent terminology. Avoid idioms, unnecessary synonyms, and ambiguous wording. Keep repository documentation in the language already established by that repository.
- Do not introduce patterns, layers, or abstractions the problem does not exhibit a symptom for.
- When two approaches are viable, present the simpler one as the recommendation.
- Never trade the rules in these documents for framework defaults without flagging the conflict.
- When a rule here conflicts with an existing codebase convention, follow the codebase and flag the divergence — consistency within a repo beats these documents.

## 7. Design reasoning protocol

Before proposing a non-trivial workflow or distributed operation, answer the questions that apply:

- What is the business operation and its stable identity?
- What happens if it executes twice or two workers execute it concurrently?
- What happens if the process dies between any two effects, and what is the last confirmed checkpoint?
- Can an external effect have an unknown result after a timeout? How is it reconciled?
- Which failures are transient, rate-limited, permanent, business, or ambiguous?
- Which completed action requires compensation, and can that compensation fail?
- Can messages be lost, duplicated, or reordered? How are publication and consumption made durable and idempotent?
- What happens when input exceeds sustainable output? Where are admission, in-flight, tenant, and provider limits enforced?
- How are stale processes detected and safely recovered?
- How can an operator reconstruct the complete flow from monitoring to durable state, logs, and traces?
- Which complexity can be postponed, what is the main trade-off now, and what concrete condition would justify evolving the design?

Explain each material decision in this order:

```text
problem
→ restrictions
→ solution
→ reason
→ main limitation
→ condition for evolution
```

Name the guarantee precisely. For example, a Redis lease can coordinate two workers, but durable business idempotency still requires a stable operation key and a database uniqueness/conditional-write guarantee.

## 8. Context to use in explanations

Ricardo has more than ten years of software-engineering experience. Do not explain from the assumption that he lacks technical foundations. Help connect known solutions to their common names and turn procedural knowledge into concise verbal reasoning.

Prefer examples grounded in his real context when they fit:

- PHP/Symfony backend systems using DDD, CQRS, TDD, events, and asynchronous workers.
- Shopify ↔ ERP integrations, especially `orders/create`, `orders/paid`, and `orders/updated` webhooks.
- Coordination between hooks, orders, inventory, invoices, partial refunds, and internal versus external state.
- React, TypeScript/JavaScript, plus experience with Node.js and Python/FastAPI.
- MongoDB as the strongest database background, with working PostgreSQL/Supabase knowledge.
- Datadog logs, monitors, alerts, dashboards, and distributed-flow investigation.
- LangChain, RAG, FAISS, Ollama, and agent-based projects.
- A modular-monolith preference unless a service boundary has a concrete justification.

Never turn that context into invented experience. Distinguish what Ricardo has demonstrated in production, what he can reason about from adjacent experience, and what remains theoretical or unverified.
