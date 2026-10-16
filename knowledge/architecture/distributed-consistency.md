# Distributed Consistency — Idempotency, Concurrency & Recovery

Distributed execution has no atomic boundary across our database, a broker, Redis, and an external provider. Design every operation by naming its stable identity, its local consistency boundary, every crash window, and how the system converges afterwards.

## 1. Event idempotency and business idempotency are different

**Event idempotency** prevents applying the same delivery twice. Persist the event ID in an inbox with a unique constraint. This is necessary under at-least-once delivery, but it only deduplicates one message.

**Business idempotency** prevents two different requests or events from producing the same business effect. A Shopify `orders/create` and `orders/paid` webhook can both attempt to create the same invoice. They have different event IDs but one business operation: `create-invoice:{tenant}:{shopifyOrderId}`.

**Hard rule**: every externally triggered effect has a durable business idempotency key derived from stable business identity, not from a delivery attempt, timestamp, random UUID, or worker ID. Enforce it with a unique constraint and store the completed result against it so retries return or converge on the same outcome.

**Why**: a queue deduplication window, a Redis lock, or an in-memory set can disappear. Correctness state belongs in durable storage.

## 2. Assume at-least-once, duplication and reordering

**Principle**: messages can be delivered more than once, concurrently, and out of order. Producers and consumers must remain correct under all three conditions.

- Deduplicate deliveries by event ID through the inbox ([reliable-messaging.md](reliable-messaging.md)).
- Deduplicate business effects by business idempotency key.
- Store an origin version or sequence per entity and reject stale events.
- If the provider gives no ordering key, re-fetch current source state or reconcile instead of trusting arrival order.
- Partitioning by `entityId` can serialize messages for one entity, but does not replace version checks: retries, replays, repartitioning, and other channels can still reorder work.

## 3. Prevent lost updates with optimistic concurrency

**Principle**: every concurrently mutable aggregate carries a version. Persistence performs a compare-and-set conditional write: update `WHERE id = ? AND version = expected`, then increments the version. Zero modified rows means a concurrency conflict, never success.

```sql
UPDATE invoices
SET status = :status, version = version + 1
WHERE id = :id AND version = :expected_version;
```

On conflict:

1. Re-read the latest aggregate.
2. Re-evaluate the complete business rule against that state.
3. Retry only if the operation still makes sense.
4. Stop after a small bounded number of attempts; sustained contention needs serialization or a redesigned hot aggregate, not infinite retries.

**Anti-patterns**: last-write-wins on business state; retrying the same stale write; checking a version in application code and then issuing an unconditional update.

## 4. Locks coordinate work; they do not prove correctness

Use a distributed lock only when concurrent execution is expensive or unsafe and a durable uniqueness/conditional-write constraint cannot express the whole coordination need. Keep the durable idempotency key and aggregate version even when a lock exists.

For a single Redis lock, acquire atomically:

```text
SET lock:{tenant}:{entity} {randomOwnershipToken} NX PX {leaseMs}
```

Use `EX {seconds}` instead of `PX {milliseconds}` when second precision is sufficient. In both forms, `SET ... NX EX|PX` performs ownership creation and expiry atomically.

**Rules**:

- The value is an unguessable ownership token unique to this acquisition.
- The TTL is a lease based on a measured upper bound, not an infinite lock.
- Renewal compares the token and extends the TTL atomically.
- Release compares the token and deletes atomically, using a server-side script/function. Never `GET` then `DEL` in two calls.
- A process that lost or failed to renew its lease stops work and must not release the new owner's lock.
- Use bounded acquisition retries with jitter; fail, defer, or requeue under sustained contention.

**Fencing rule**: an ownership token stops one worker deleting another worker's lock, but it does not stop a stale worker writing after its lease expired. When stale writes matter, issue a monotonically increasing fencing token and require the protected resource to reject tokens older than the latest accepted one. If the resource cannot enforce fencing, rely on conditional writes and idempotent convergence rather than claiming the lock gives mutual exclusion.

## 5. Durable ownership and stale process recovery

Long work is owned through persisted leases, not process memory. A claim records:

```text
owner_id
lease_expires_at
heartbeat_at
attempt
updated_at
```

Workers claim available or expired work through one atomic conditional update. They heartbeat only while making progress. Another worker may reclaim an expired lease, resume from the last durable checkpoint, and use version/fencing checks to prevent the old worker from committing stale progress.

**Stale detection**: `processing` is not proof that a process is alive. Alert and recover when the heartbeat or lease is older than its documented threshold. Recovery must be automatic for safe cases and route ambiguous cases to reconciliation or manual review.

## 6. Checkpoints describe confirmed progress

**Principle**: a resumable process persists the last completed step or chunk after that unit's effects are durable. Prefer `lastCompletedStep` over `currentStep`: the former says what is safe to skip after a crash; the latter can describe work that never finished.

Every step and checkpoint is idempotent. Commit the step's local state and its checkpoint atomically where possible. If not possible, order operations so replay is safe and document the crash window.

## 7. A timeout creates an unknown outcome

A timeout means we did not receive a result. It does not mean the provider did not execute the request.

**Rules for external side effects**:

- Send a stable provider idempotency key when the API supports one.
- Persist the request identity before sending it.
- After an ambiguous timeout, mark `external_result_unknown`; do not blindly repeat a non-idempotent call.
- Query the provider by idempotency key or external reference.
- Reconcile until the outcome is known, then apply the local transition exactly once.
- If the provider offers no query or idempotency mechanism, expose the ambiguity and route it to manual review. Never invent certainty.

## 8. Strong consistency is local; convergence is global

Use strong consistency for invariants inside one aggregate and one durable transaction. Across aggregates, queues, caches, and external providers, use eventual consistency with explicit versioning, retries, reconciliation, and observable lag.

**Decision format for distributed work**:

```text
business operation
→ stable identity
→ concurrency boundary
→ crash windows
→ durable checkpoint
→ ambiguous external effects
→ retry/reconciliation policy
→ observable terminal outcome
```

For every design, answer: what happens if it runs twice, two workers run it together, the process dies between steps, an old event arrives, or the external call succeeds but its response is lost?
