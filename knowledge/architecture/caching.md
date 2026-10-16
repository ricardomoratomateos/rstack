# Caching — In-Process and Distributed

**Framing principle**: a cache is an optimization, never a design element. Two very different tools share the word "cache": a **per-unit-of-work memo** (free, cannot desync beyond its own scope) and a **shared distributed cache** (Redis: TTL, invalidation, a brand-new failure mode in your read path). Always try the first one before the second, and never add either before measuring the cost you claim to remove ([00-manifesto.md](../00-manifesto.md): KISS, YAGNI).

## Where a cache lives

### 1. The domain never knows there is a cache

**Principle**: No cache import, no cache parameter, no TTL constant anywhere in `domain/`. Caching is applied in infrastructure as a decorator over a port and wired in the container ([hexagonal.md](hexagonal.md)).

**Why**: A cache is a deployment-time performance decision. The moment a business rule branches on cache state, that rule can't be tested or reasoned about without infrastructure, and correctness starts depending on warmth.

**Anti-patterns**:
- `if (await this.cache.get(key)) ...` inside a command handler or a domain service.
- A repository port exposing `findByIdCached()` — the port describes *what* is needed, not how fast it comes back.
- TTLs hardcoded in domain constants.

### 2. Cache-aside as a decorator adapter — the only shape

**Principle**: The cache is an adapter implementing the same port as the real one, wrapping it. Consumers never change; removing the cache is deleting one line of wiring.

```ts
class CachedTaxRateRepository implements TaxRateRepository {
  constructor(
    private readonly inner: TaxRateRepository,
    private readonly cache: Cache,
  ) {}

  async findFor(country: CountryCode, tenant: TenantId): Promise<TaxRate | null> {
    const key = CacheKey.taxRate(tenant, country);
    const hit = await this.cache.get(key);
    if (hit) return TaxRate.fromPrimitives(hit);          // rehydrated, validated

    const rate = await this.inner.findFor(country, tenant);
    if (rate) await this.cache.set(key, rate.toPrimitives(), Ttl.hours(6));
    return rate;
  }
}

// container
new CachedTaxRateRepository(new MongoTaxRateRepository(db), redisCache);
```

**Corollary**: the same test suite must pass against the wrapped and the unwrapped implementation (rule 11).

### 3. Keys are built by a VO, namespaced, tenant-scoped and versioned

**Principle**: A generic technical `Cache` port (`get` / `set` / `delete` / `getOrSet`, TTL always explicit) in the shared kernel is fine. What is not fine is string concatenation of keys scattered across adapters. Keys come from a `CacheKey` value object ([value-objects.md](../domain/value-objects.md)).

```
{app}:{context}:{entity}:v{n}:{tenant}:{id}
```

**Rules**:
- **Tenant is never optional** in a key. Same reason as `ExternalReference.sourceTenant` ([async-workers.md](async-workers.md) rule 6): the same ID exists in two accounts, and a cross-tenant cache hit is a data leak, not a bug.
- **The `v{n}` segment is bumped whenever the cached payload's shape changes.** Deploys then never read yesterday's shape; no migration, no mass flush, old keys die by TTL.
- One namespace per concept, so hit rate is measurable per namespace (rule 14).

## In-process caches — the unit-of-work memo

### 4. Repeated reads inside one operation → memoize, don't Redis

**Symptom**: a sync fetching the same order 7 times; the same tax rate resolved once per invoice line; the same customer loaded once per order in a batch.

**Principle**: The first-choice fix is an in-process memo whose lifetime is the current unit of work — one HTTP request, one consumed message, one job run. It needs no TTL, no invalidation, no serialization and no network, and it physically cannot serve data staler than the operation itself.

```ts
// scoped per unit of work — one instance per request / message / job
class MemoizingOrderRepository implements OrderRepository {
  private readonly identityMap = new LruMap<string, Order>(MAX_ENTRIES);

  constructor(private readonly inner: OrderRepository) {}

  async findById(id: OrderId): Promise<Order | null> {
    const key = id.value;
    const known = this.identityMap.get(key);
    if (known) return known;

    const order = await this.inner.findById(id);
    if (order) this.identityMap.set(key, order);
    return order;
  }

  async save(order: Order): Promise<void> {
    await this.inner.save(order);
    this.identityMap.set(order.id().value, order);        // never read your own stale write
  }
}
```

**Rule**: reach for Redis only when the win crosses process or request boundaries. "7 reads in one sync" does not — it's a memo, and the memo is free.

**Resolvers are the natural home of these memos** — see [design-patterns.md](../design-patterns.md) rule 9.

### 5. The scope is injected, never static

**Principle**: The memo lives in an object created by the container **once per unit of work**. In long-lived workers, a fresh scope is opened per consumed message.

**Why**: A process-level memo leaks entities from one message to the next and, worse, from one tenant to the next — the same failure as request context in statics ([observability.md](observability.md) rule 4).

**Hard rules**:
- No module-level `Map`, no `static` cache, no singleton "CacheService" holding entity data for the process lifetime.
- If a test needs to reset a global for the next test to pass, the design is already wrong ([architecture-tests.md](../testing/architecture-tests.md)) — and it's worth an architecture test forbidding mutable module-level state in these classes.

### 6. Bounded, and coherent with writes

**Principle**: Every in-process map has a maximum size with LRU eviction, and every write path updates or evicts its entry.

**Why**: An unbounded map inside a 500k-row import is a memory leak with a deploy-shaped fix. And a memo that isn't updated on `save` makes the job read state it just changed itself — the classic memo bug.

**Identity map rule**: within one unit of work, the same ID returns the *same instance*. Two live instances of one aggregate in a single operation is a lost update waiting to happen.

## Shared cache (Redis)

### 7. Explicit TTL and an owner, always

**Principle**: Every entry has a TTL and a documented staleness budget — "this may be up to 6 hours old, and that is acceptable because X". No infinite TTLs.

**Tiers I use**:
- Reference/config data (tax rates, catalogs, feature config): hours.
- Computed read models and expensive aggregations: minutes.
- Per-user/volatile data: seconds, or don't cache it.

**Never cached without an explicit, written decision**: authorization/permission results, balances and anything money-deciding ([money-precision.md](../domain/money-precision.md)), and rate-limit counters (those are state, not cache — rule 12).

### 8. Invalidate on write; TTL is the safety net

**Principle**: Primary invalidation is explicit — the write path, or a subscriber to the domain event describing the change ([event-driven.md](event-driven.md)), evicts or refreshes the key. TTL is the backstop for the invalidations you missed.

**Why**: This is the same architecture as webhooks plus reconciliation ([async-workers.md](async-workers.md) rule 4): a fast, precise path, and a slower mechanism that guarantees convergence anyway.

**Hard rule**: a cache whose only invalidation is TTL serves known-wrong data for the length of that TTL *by design*. That's a legitimate choice for reference data — but it must be a stated choice, not the default because eviction was never wired.

### 9. Cache read models, never aggregates

**Principle**: What goes into Redis is an immutable DTO or projection ([cqrs.md](cqrs.md)), not a serialized aggregate. On read, the payload is rehydrated through the same validation as any external input.

**Why**: Restoring an aggregate from a blob bypasses its invariants and loses its concurrency version — you get a behavior-bearing object that was never constructed legally. And the cache *is* untrusted input: that blob may come from a previous deploy or another service version.

**Anti-patterns**: `JSON.parse` straight into a domain entity; caching an aggregate that carries an optimistic-locking version; storing objects whose shape isn't covered by the `v{n}` key segment (rule 3).

### 10. Negative caching and stampede control

**Principle**: Cache "not found" too, with a short TTL — otherwise every miss goes to the source, and a hot missing key is a classic self-inflicted outage. On expiry of a hot key, use single-flight (one loader recomputes, the rest wait) or jittered TTLs.

**Why**: N workers recomputing the same expensive value in the same second is how adding a cache *causes* the incident it was meant to prevent.

## Correctness and operations

### 11. A cache miss is slower, never different

**Hard rule**: Behavior with a cold or disabled cache is identical in every observable way. Unit and integration tests run against a `NullCache` (null object — [design-patterns.md](../design-patterns.md) rule 8) or an in-memory fake; never a real Redis. At least one test path exercises the cached decorator itself, asserting the same expectations as the undecorated one.

**Why**: If a feature only works warm, it isn't a cache — it's an undeclared database with no durability.

### 12. Redis down must degrade, not fail

**Principle**: Every cache call has a timeout, and failures fall through to the source: logged, request served. A cache without a timeout is a new single point of failure inserted into your read path. Failures *writing* to the cache are non-events.

**Anti-patterns**:
- An unavailable cache producing 500s.
- Storing in the cache namespace anything whose loss changes correctness (idempotency keys, outbox state, counters). Those need a store with durability guarantees — sharing the Redis instance is fine, sharing "it's just cache, we can flush it" semantics is not.

### 13. Don't cache a missing index

**Principle**: Before caching a slow query, explain it ([mongodb.md](../databases/mongodb.md)). A cache in front of a collection scan hides the actual defect, still pays full cost on every miss, and adds staleness on top.

**Cache is for what is genuinely expensive**: remote API calls, heavy aggregations, cross-service reads, render/compute results. Not for a query that needs an index.

### 14. Hit ratio is a metric, or the cache isn't justified

**Principle**: Per-namespace hit rate, miss latency, error rate and evictions, tagged by tenant like everything else ([observability.md](observability.md) rule 3).

**Why**: A cache you can't measure can neither be defended nor removed. If the hit rate is low, delete it — you're paying complexity and staleness risk for nothing.

## Adaptation

- **No Redis available**: a per-process LRU with a short TTL is acceptable for reference data (accepting per-instance divergence), never for data users must see consistently across instances.
- **Serverless / short-lived processes**: the unit-of-work memo still applies per invocation; a shared cache becomes relatively more valuable because nothing else survives between invocations.
- **Read-heavy HTTP endpoints**: `ETag`/`Cache-Control` at the edge is the cheapest cache there is — evaluate it before building an application-level one.
- **Frameworks with cache pools built in** (Symfony Cache, Nest `CacheModule`, Spring `@Cacheable`): they are adapters. The port stays ours, and annotation-driven caching that hides itself on a service method violates rule 1 and explicitness ([00-manifesto.md](../00-manifesto.md) rule 3).
