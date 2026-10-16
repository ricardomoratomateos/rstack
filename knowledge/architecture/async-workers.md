# External Events, Webhooks & Async Workers

Hard-won lessons from integrating with external platforms (Shopify above all). Applies to any third-party sending us webhooks/events, and to our own background jobs.

## Webhook ingestion

### 1. Receiving ≠ processing

**Principle**: The webhook HTTP endpoint does exactly three things: verify the signature (HMAC), persist the raw event, respond 200. All processing happens in a worker afterwards. No business logic in the HTTP handler, ever.

**Why**: Providers time out and penalize slow endpoints (Shopify deregisters webhooks that respond slowly). Decoupling receipt from processing also means a processing bug never loses events.

### 2. Assume at-least-once AND out-of-order delivery

**Principle**: Duplicates arrive. Events arrive out of order. Every consumer dedups by event ID and compares the event's origin version/timestamp against the stored `ExternalReference` (rule 6) before applying changes. An event older than what we already hold is discarded (logged as stale), never applied.

**Anti-patterns**: "last webhook received = current state". It isn't.

### 3. A webhook is a notification, not the truth

**Principle**: For critical decisions, re-fetch the resource from the source API. The webhook payload is usable directly only where slightly stale data is tolerable.

### 4. Webhooks get lost — reconcile

**Principle**: A periodic reconciliation job compares local state against the source and repairs gaps. The system must converge even if not a single webhook arrives.

**Why**: Every webhook provider drops events eventually — outages on either side, deregistrations, bugs. Reconciliation is not optional hardening; it's the actual sync mechanism, with webhooks as the low-latency fast path.

### 5. Persist the raw event (inbox)

**Principle**: Store the raw payload in an inbox table/collection before processing: enables reprocessing, auditing, and debugging. Processing reads from the inbox, marks progress, and is resumable.

## Provenance: the ExternalReference VO

### 6. Every synced entity carries an `ExternalReference` VO

**Principle**: Anything synced from an external system stores a mandatory `ExternalReference` value object — never a bare `externalId: string`. Capture the maximum information at ingestion time, even fields with no consumer today.

```ts
ExternalReference {
  source           // "shopify"
  sourceTenant     // shop domain / store id — NEVER optional
  externalId       // resource ID at the source
  externalVersion  // ordering key: event id, sequence number
  emittedAt        // when the SOURCE emitted/updated it (origin clock)
  raw?             // raw payload or pointer to the inbox event
}
```

**Rules**:
- **All timestamps in the VO belong to the source.** `emittedAt` is Shopify's clock. Our own ingestion/update time lives outside the VO, in the entity's standard `createdAt`/`updatedAt`.
- If the source offers both a timestamp and a version/event id, **store both**: timestamp for humans and reconciliation, version for precise ordering (two updates in the same second tie on `updated_at`).
- **Out-of-order guard**: incoming event's version/`emittedAt` is compared against the stored VO; older ⇒ discard (rule 2). The watermark lives **on the synced record itself**, never in a separate cursor table — it survives replays, reprocessing, and restores for free, with no extra store to keep consistent.
- **Idempotency key**: `(source, sourceTenant, externalId)` uniquely identifies the external resource; upserting against that tuple makes reprocessing safe.
- **Reconciliation key**: the reconciliation job (rule 4) uses the VO to know which tenant and resource to compare.
- **Multi-tenant from day one**: the same `externalId` can exist in two shops.
- Like every VO ([value-objects.md](../domain/value-objects.md)): immutable, self-validated, equality by value.

**Why capture everything**: recovering provenance after the fact is expensive or impossible; storing it at ingestion is free.

## Workers & background jobs

### 7. Every job is idempotent — by convergence when possible

**Principle**: Jobs WILL re-run: retries, redeploys, crashes mid-execution. Design every job so that running twice equals running once.

**The strongest form is convergence**: structure the operation as `f(input, current_state)` where processing the same fact twice yields a no-op *mathematically* (the second pass computes "nothing to change"), instead of relying on dedup bookkeeping. Convergent operations also make two independent channels reporting the same fact harmless — no coordination needed between them.

### 8. Retries with exponential backoff + dead letter queue

**Principle**: Retry only classified transient/rate-limit failures with a bounded policy. A job exhausting its policy goes to a DLQ with full context for controlled redrive or manual inspection. Never silently drop work or retry forever. Full rules: [resilience.md](resilience.md).

### 9. Small, single-responsibility jobs

**Principle**: A job doing 5 things that fails at step 3 is an idempotency problem. Prefer 5 chained jobs, or one orchestrating job with re-entrant steps.

### 10. Fair queues — one tenant must never starve the rest

**Principle**: Work queues are fair by tenant. A client enqueueing 100k jobs (bulk import, huge shop) must not delay every other client's jobs. Fairness is a design requirement of the queue, not an ops tweak after the incident.

**How I apply it**:
- Per-tenant sub-queues with round-robin consumption, or per-tenant concurrency caps — never a single FIFO where one tenant can flood the head.
- The same applies outbound: third-party rate limits are enforced per tenant (per shop), so one big shop exhausting its API budget doesn't block the rest.

**Anti-patterns**: a global queue where job order = insertion order; per-process rate limiting that lets one tenant consume the whole budget.

### 11. Prioritize by business importance

**Principle**: Not all async work is equal — queues are segmented by priority based on business impact. Example from ecommerce sync: **syncing orders is more important than syncing products** (an unsynced order is money and fulfillment at risk; a stale product description is not).

**How I apply it**:
- Separate queues (or priority levels) per criticality: e.g. `orders` consumed before/with more workers than `catalog`.
- Priority is decided per job *type* by business impact, not per tenant and not FIFO.
- Low-priority backlog must never block high-priority consumption (separate workers/pools, not just a priority field in one queue).

**Rule for agents**: when adding a new async job type, state its priority class explicitly and justify it in business terms.

### 12. Outbox pattern for publishing our own events

**Principle**: Events are written in the same transaction as the state change; a publisher relays them afterwards. Never publish to a bus inside the transaction, nor after commit without a delivery guarantee.

The relay can publish twice if it fails before marking delivery. Consumers still require an inbox and idempotent business effects. Full failure windows: [reliable-messaging.md](reliable-messaging.md).

### 13. Rate limit everything — and a limit that doesn't block is not a limit

**Principle**: Rate limits apply everywhere, as a security measure, not just as capacity management:

- **Inbound**: every public API/token gets per-key and per-tenant limits — abuse containment, not just fairness.
- **Outbound**: respect third-party limits on **reads too**, not only writes (polling/fetching against a provider consumes the same budget as pushing).
- Limits are per tenant/key, never per process or global (see rule 10 — fairness).
- Rate and concurrency limits are separate controls; distributed algorithms, `Retry-After`, circuit breakers, and bulkheads are defined in [resilience.md](resilience.md).

**Hard rule**: a rate limiter configured to only log/emit-an-event when exceeded is monitoring, not a limit. It must actually block — and the documented limits must match the enforced ones.

**How to block depends on who is calling**:
- **Your API clients**: reject with an honest 429 — they can and must back off.
- **Webhook providers (Shopify etc.)**: never reject — too many 4xx/5xx responses get the integration deregistered. Always accept fast (200) and shed load *behind* the endpoint: the limit is applied at the queue/worker layer (per-tenant throttling, rule 10), not at the HTTP edge. This is another reason receiving ≠ processing (rule 1).

### 14. Queue observability is a first-class metric

**Principle**: Queue depth, age of the oldest job, and DLQ rate — with alerts. A silent backlog is an incident on a delay timer.

## Adaptation

- These rules are provider-agnostic: Stripe, GitHub, or any webhook source has the same delivery semantics (at-least-once, unordered, lossy).
- Shopify specifics worth remembering: webhook timeout/deregistration behavior, per-shop rate limits, GraphQL cost-based throttling, bulk operations as the reconciliation fast path for large datasets.
