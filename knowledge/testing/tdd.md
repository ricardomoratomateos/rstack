# TDD & Testing Discipline

## 1. TDD by default for behavior that benefits from design feedback

**Principle**: For domain behavior, value objects, use cases, bug fixes, and state transitions, use Red → green → refactor. The test is written before the implementation, fails for the right reason, then the minimal implementation makes it pass.

**Why**: Tests written first define the behavior contract and keep the design honest (hard-to-test code is badly designed code). Tests written after tend to certify whatever the code happens to do.

**Rule for agents**: when implementing a use case or domain behavior, write the failing test first and show it failing before implementing. Do not force a ceremonial test-first cycle onto trivial wiring, generated code, exploratory spikes, or changes whose valuable proof is necessarily an integration check. State the chosen verification instead.

## 2. Test behavior, not implementation

**Principle**: Tests target the use case or the domain's public API — given this command/input, this outcome/event/state. Never internal details: private methods, call order, internal structure.

**Why**: Implementation-coupled tests break on every refactor, which trains people to delete or rubber-stamp them. Behavior tests survive refactors — that's their entire value.

**Anti-patterns**:
- Asserting that a specific internal method was called with specific arguments (mock choreography).
- Tests that must change when behavior didn't.

## 3. Domain tested without infrastructure

**Principle**: Domain and application tests are pure unit tests: real domain objects, in-memory fakes for ports (repositories, clock, bus). No DB, no network. Adapters get their own integration tests against real infrastructure.

**How I apply it**:
- `InMemoryInvoiceRepository` implementing the port, for handler tests.
- `FixedClock` — time is a port ([hexagonal.md](../architecture/hexagonal.md)), so tests never sleep or race.
- Integration tests for `MongoInvoiceRepository` verify the real queries (including index fit — [mongodb.md](../databases/mongodb.md)).

**Anti-patterns**: mocking library sprawl — prefer hand-written fakes implementing the port over mock-framework stubs; fakes get reused and stay honest.

## 4. Object mothers / builders for fixtures

**Principle**: Test data comes from object mothers or builders that produce **valid** objects by default, leveraging the VOs ([value-objects.md](../domain/value-objects.md)). Each test overrides only what matters to it.

```ts
InvoiceMother.pending();                        // valid pending invoice, don't care about details
InvoiceMother.pending({ total: AmountMother.eur(100_00) }); // this test cares about the total
```

**Why**: inline fixture construction duplicates setup everywhere and obscures what each test actually cares about.

## 5. A test that cannot fail is worthless

**Principle**: No tests for getters, no asserting mocks against mocks, no snapshot tests nobody reads. Every test must be able to catch a plausible regression; if you can't name the bug it would catch, delete it.

**Corollary — coverage is a byproduct, not a goal**: chasing a coverage number produces exactly these worthless tests.

## What gets tested, priority order

1. Domain invariants and VO validation (cheapest, highest value).
2. Use cases / command & query handlers (with fakes).
3. Adapters via integration tests (repositories, external API clients — including webhook/event consumers' idempotency and out-of-order handling, [async-workers.md](../architecture/async-workers.md)).
4. A thin end-to-end smoke layer. Not an inverted pyramid of E2E suites.

This is a pyramid, not a prohibition: acceptance and contract tests are added where module/provider behavior requires them. Distributed failure scenarios and test-double roles are defined in [distributed-systems.md](distributed-systems.md).
