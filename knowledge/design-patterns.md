# Design Patterns — Symptom → Pattern Map

**Framing principle**: patterns are tools against concrete symptoms, not decoration. Apply a pattern when its symptom appears; do NOT apply it when it doesn't ([00-manifesto.md](00-manifesto.md): KISS, YAGNI). Every applied pattern must be justifiable by pointing at the symptom it removes.

## 1. Huge constructor → Builder / named constructors

**Symptom**: a constructor beyond ~3-4 parameters, several optionals, or boolean flags; call sites where you can't tell what each positional argument is.

**Pattern**: builder, or static factory methods with intention-revealing names.

```ts
// BAD
new Invoice(customerId, lines, true, false, null, 'EUR', new Date());

// GOOD
Invoice.draft(customerId, lines);
Invoice.fromLegacyImport(customerId, lines, importedAt);
InvoiceBuilder.for(customerId).withLines(lines).asDraft().build();
```

**Hard rule**: long positional constructors are forbidden. Named constructors also encode *which* valid states exist (a draft vs an imported invoice), reinforcing self-validating construction ([value-objects.md](domain/value-objects.md)).

**Corollary — never distinguish cases by a nullable parameter or boolean flag**: if `new Thing(x, null)` means one case and `new Thing(x, y)` means another, each case gets its own named constructor (`Thing.opens(x)` / `Thing.corrects(x, y)`). The constructor name carries the case; nothing is inferred from null-ness.

## 2. Nested if/else or switch on "type" → Strategy / polymorphism

**Symptom**: the same `switch (type)` / `if (country === ...)` appears in more than one place, or business branches by type/country/plan keep growing.

**Pattern**: strategy interface + one implementation per variant + a selector (a registry/map, NOT another giant if).

```ts
// BAD — this switch will appear again somewhere else next month
if (provider === 'shopify') { ... } else if (provider === 'amazon') { ... }

// GOOD
interface OrderImporter { supports(provider: Provider): boolean; import(raw: RawOrder): Order; }
const importer = importers.find(i => i.supports(provider)); // registry
```

**Registry hard rule — fail fast on duplicates**: when strategies self-register (DI tags, plugin discovery), the registry **throws at construction time** if two implementations claim the same key, and lookup misses throw a typed exception. Conflicts surface at boot/deploy, never as silent wrong-strategy selection in runtime.

**Not a symptom**: a single two-branch `if` that exists in exactly one place. Leave it alone.

## 3. Chains of validations/steps → Chain of Responsibility / pipeline

**Symptom**: sequential steps that are interchangeable, optional, or reorderable (validation chains, enrichment steps on an incoming webhook, authorization checks, discount rules applied in order).

**Pattern**: a chain of small handlers behind one interface, each able to handle, enrich and continue, or stop the chain.

```ts
interface OrderIngestionStep {
  handle(context: IngestionContext, next: NextStep): Promise<IngestionResult>;
}

// wired in ONE place — the order is the configuration
new IngestionPipeline([
  new RejectStaleEvent(),        // may short-circuit
  new ResolveCustomer(),         // enriches the context
  new ResolveProducts(),
  new ApplyTaxes(),
]);
```

**Rules**:
- **The order is explicit and lives in one place** (a list at wiring time). Never derived from annotation discovery, file names, or DI tag order — implicit order is a bug you can't read.
- **Handlers don't know each other**: a handler never instantiates or names the next one. It calls `next` (or returns a decision the pipeline acts on).
- **Short-circuit semantics are documented and uniform**: either the chain stops at the first failure or it collects every error and reports them together. Pick one per chain, state it, and don't mix. Expected outcomes travel as typed results, not as exceptions used for control flow.
- **No shared mutable state between handlers**: everything a handler needs arrives in the context it receives, and what it contributes goes back into the context explicitly.
- **Each handler is testable alone**, with a fake `next` asserting whether it continued or stopped.
- **Reuse the framework's middleware if it already is a chain** (HTTP middleware, message-bus middleware): don't build a second pipeline mechanism next to the one you already run on.

**Not a symptom**: steps that are fixed and always all run in the same order — a plain sequence of function calls is simpler and clearer. Don't pipeline it.

**Anti-patterns**: a chain of 15 handlers that *is* the use case (the pipeline became the god-class); handlers whose correctness depends on an order nothing documents; `next()` called conditionally in ways that make the traversal unpredictable.

## 4. Creation with variants → Factory

**Symptom**: consumers deciding which implementation to instantiate, with the decision logic duplicated.

**Pattern**: centralize the "which implementation" decision in a factory; consumers depend on the port ([hexagonal.md](architecture/hexagonal.md)).

## 5. Coupled side effects → Observer / events

**Symptom**: a use case doing its job *and* triggering unrelated reactions inline.

**Pattern**: domain events + subscribers. Full rules in [event-driven.md](architecture/event-driven.md).

## 6. Behavior changing with state + boolean flags → State

**Symptom**: `isDraft`, `isSent`, `isPaid` flags combined in ifs; illegal flag combinations possible.

**Pattern**: explicit states (enum/VO or state classes) where each state knows its allowed transitions. `invoice.send()` on a paid invoice fails in the state logic, not in scattered guards.

## 7. External APIs touching the domain → Adapter / Anti-Corruption Layer

**Symptom**: third-party models (Shopify's order shape, a bank's payload) leaking into domain entities or use case signatures; SDK exceptions caught in a command handler; a `raw` field travelling through the application layer.

**Pattern**: an adapter at the boundary. Two jobs that always go together:

1. **Implement our port** with the vendor's SDK — the port's signature is ours, never the vendor's ([hexagonal.md](architecture/hexagonal.md) rule 2).
2. **Anti-Corruption Layer**: translate the external model into our domain language — VOs ([value-objects.md](domain/value-objects.md)) and an `ExternalReference` ([async-workers.md](architecture/async-workers.md) rule 6). The third party's naming, structure and units stop here.

```ts
// infrastructure/shopify/ShopifyOrderGateway.ts
class ShopifyOrderGateway implements OrderGateway {   // port owned by the inside
  async fetch(ref: ExternalReference): Promise<Order> {
    const raw = await this.client.order(ref.externalId);   // SDK lives only here
    return ShopifyOrderTranslator.toDomain(raw, ref);      // total, explicit translation
  }
}
```

**Rules**:
- **The translation is total and explicit**: every domain field is mapped from a named source field. Unknown or missing values either fail loudly with a typed error or take a documented default — never `as any`, never spread-through of the vendor payload.
- **Units and money are converted at the boundary**, once (`"12.30"` strings, cents, tax-inclusive vs exclusive — see [money-precision.md](domain/money-precision.md)). A unit mismatch that reaches the domain is unfindable later.
- **The adapter owns the mechanics of that provider**: timeouts, retries, pagination, rate limits ([async-workers.md](architecture/async-workers.md) rule 13), and translating vendor errors into typed domain errors. Nothing above it knows the provider had a 429.
- **One adapter per provider per capability.** A single adapter branching on provider inside is Strategy misapplied (rule 2).
- **Contract-tested with recorded real payloads** as fixtures, including the ugly ones (missing customer, refunded line, zero-price item). The translator is the highest-value unit test in an integration.

**Anti-patterns**: DTOs shaped like the provider reaching the application layer; the raw payload used as "the model" because "it already has everything"; an adapter that also decides business outcomes instead of just translating.

## 8. Repeated null checks → Null Object / explicit optional types

**Symptom**: the same `if (x === null)` guard sprinkled everywhere for the same concept.

**Pattern**: a null object with neutral behavior, or the language's explicit optional/maybe type. Pick per language; the goal is one place that handles absence.

## 9. Repeated "which existing thing does this input mean?" → Resolver

**Symptom**: the same lookup-then-create dance duplicated across importers, handlers or jobs — search by external reference, else search by natural key (SKU, email, tax id), else create with defaults — each copy slightly different. Or: several callers each mapping an external code to an internal entity their own way.

**Pattern**: a **Resolver** — one small application service per concept whose only job is turning ambiguous outside-world input into exactly one domain object (existing or newly created).

```ts
interface CustomerResolver {
  resolve(input: CustomerResolutionInput): Promise<Customer>;   // never null
}

class ShopifyCustomerResolver implements CustomerResolver {
  constructor(
    private readonly customers: CustomerRepository,   // memoizing decorator, scoped per job
    private readonly clock: Clock,
  ) {}

  async resolve(input: CustomerResolutionInput): Promise<Customer> {
    // 1. by ExternalReference (source, sourceTenant, externalId)
    // 2. by natural key (tenant + email)
    // 3. create with the documented defaults
  }
}
```

**Rules**:
- **One concept per resolver** (`CustomerResolver`, `ProductResolver`, `TaxRateResolver`). A `SyncResolver` resolving five things is the import script wearing a pattern's name.
- **Total function**: it returns the resolved object or throws a typed domain error (`AmbiguousCustomer`, `UnmappableTaxRate`). It never returns null and never leaves the fallback to the caller — deciding the fallback *is* the pattern's content.
- **The resolution order is explicit and documented**, most specific first: external reference ([async-workers.md](architecture/async-workers.md) rule 6) → natural key → create. Every step's criteria include the tenant.
- **Find-or-create is concurrency-safe**: a unique index over the natural key, and on duplicate-key error re-read and return the winner. Two workers resolving the same customer at the same instant must not create two.
- **Memoized per unit of work**: resolving the same SKU 400 times in one import hits the database once ([caching.md](architecture/caching.md) rules 4-6). The memo is scoped to the job, never static.
- **Resolvers resolve; they don't sync**: no updating the found entity with the incoming payload, no emitting business events. The caller decides what to do with what it got back.
- **It is neither a Factory nor a Repository**: a factory constructs, a repository fetches or persists by known identity, a resolver decides *which* identity an external input refers to.

**Not a symptom**: one caller doing one lookup by ID. That's a repository call.

## 10. `if (isLeaf)` over a tree → Composite

**Symptom**: recursive or nested structures where callers branch on "is this one thing or a group of things?" — nested product categories, permission groups containing groups, discount rules combining rules, composed validators, bundle items with sub-items.

**Pattern**: leaf and composite implement the **same** interface; the composite holds children and aggregates their results. Callers can't tell them apart and never type-check.

```ts
interface PricingRule { apply(line: OrderLine): Discount; }

class PercentageRule implements PricingRule { ... }          // leaf

class AllOf implements PricingRule {                         // composite
  constructor(private readonly rules: readonly PricingRule[]) {}
  apply(line: OrderLine): Discount {
    return this.rules.reduce((acc, r) => acc.plus(r.apply(line)), Discount.none());
  }
}
```

**Rules**:
- **One interface, no `instanceof` at call sites.** If a caller needs to know whether it holds a leaf, the composite isn't earning its place.
- **The empty composite is neutral, not an error**: `AllOf([])` returns the identity element (`Discount.none()`, `true`, `Amount.zero()`), which is the Null Object rule (rule 8) applied to trees.
- **Aggregation semantics are documented per composite**: sum, AND, OR, first-match. Two composites with different semantics get different names (`AllOf` / `AnyOf`), never a boolean flag ([00-manifesto.md](00-manifesto.md) rule 3).
- **Trees built from data or user config get a depth limit and a cycle check** at construction. A composite assembled from a database table will eventually contain a cycle, and infinite recursion in a worker is an outage.
- **In-memory shape ≠ storage shape**: how the tree persists (materialized path, ancestor array, adjacency list — see [mongodb.md](databases/mongodb.md)) is an infrastructure decision made for the queries you need. The repository rebuilds the composite; the domain never sees paths.
- **Composite composes the other patterns**: a composite of strategies (rule 2) or of chain handlers (rule 3) is how several rules become "one rule" at a call site.

**Not a symptom**: a fixed two-level structure that will never nest (invoice → lines). That's a collection with a `total()` method.

## 11. "We need exactly one instance" → container scope, NOT Singleton

**The pattern is banned; the need is real.** Wanting one instance of a connection pool, an HTTP client, a metrics registry or a reference-data cache is legitimate. Implementing it as the Singleton *pattern* — a static accessor plus global mutable state — is not, in any of my codebases.

**How I apply it**: instance count is a **lifecycle** concern, so it's the DI container's job. Register the dependency as a container-scoped single instance; consumers keep receiving it through the constructor, typed as a port ([hexagonal.md](architecture/hexagonal.md) rule 5). Nothing anywhere calls `Whatever.getInstance()`.

```ts
// BAD — hidden dependency, global state, untestable
class ExchangeRates {
  private static instance: ExchangeRates;
  static getInstance() { return (this.instance ??= new ExchangeRates()); }
}
rates = ExchangeRates.getInstance().for('EUR');   // invisible in every signature

// GOOD — one instance, declared in the container, visible in the constructor
constructor(private readonly rates: ExchangeRateProvider) {}
```

**Why the pattern is rejected**:
- **The dependency becomes invisible.** It doesn't appear in any signature, so nobody can tell what a class actually needs, and nothing can be substituted in a test.
- **Global mutable state leaks across tests** — the failing test is the victim, not the polluter ([architecture-tests.md](testing/architecture-tests.md)).
- **It leaks across messages and tenants** in long-lived workers: a static holding request context or cached entities is the exact failure described in [observability.md](architecture/observability.md) rule 4 and [caching.md](architecture/caching.md) rule 5.
- **Lifetime stops being configurable**: you can no longer choose per-request, per-message or per-process scope, which is precisely the choice that keeps caches and context correct.

**When a third party forces a singleton on you** (SDKs with static config, framework facades): wrap it in an adapter (rule 7) and inject the adapter. The static touches exactly one file, and everything above it stays injectable.

**Enforce it**: an architecture test forbidding `getInstance`, static factories returning cached instances, and mutable static/module-level state outside the container's wiring.

**Anti-patterns**: `Registry`/`ServiceLocator`/`Container::get()` called from inside a class (a singleton with extra steps); static config read from domain code; "it's stateless, so a static is fine" — until someone adds a field to it.

## 12. Anti-rules

- **No Singleton.** Use dependency injection; scope is the container's job (rule 11).
- **No speculative patterns** ("strategy, in case more providers come"). The second variant justifies the pattern; the first doesn't.
- **No pattern soup**: if introducing a pattern makes the diff bigger than the problem, the pattern loses.
