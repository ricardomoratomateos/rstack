# Idempotency — Repeat-Safe Operations

Every operation that crosses a process boundary will run more than once: a client retries a timeout, a broker redelivers, a worker reclaims an expired lease, an operator replays a batch. Idempotency is the property that the second run produces the same state and the same answer as the first, and it is designed in, never discovered later.

This document is about making one operation repeat-safe: the shape of the write, the key, and the response. For the distributed-execution side of the problem — event vs business idempotency, optimistic concurrency, locks, leases, checkpoints, ambiguous external outcomes — see [distributed-consistency.md](distributed-consistency.md). For delivery deduplication by `eventId`, see the inbox in [reliable-messaging.md](reliable-messaging.md).

## 1. Idempotent by construction beats idempotent by bookkeeping

**Principle**: Before adding a dedup table, try to express the effect as a write that is naturally repeatable. Absolute writes, upserts on a unique key, and set semantics are idempotent by their own shape and need no extra state.

**Why**: Bookkeeping is state that can be lost, expire, or drift from the effect it guards. A write that converges on the same result no matter how many times it runs cannot drift, because there is nothing to keep in sync.

**How I apply it**:
- Prefer absolute over relative: `SET status = 'paid'` is repeatable, `INCREMENT attempts` is not. When a counter must be exact, derive it from durable facts instead of accumulating it.
- Prefer upsert on business identity over "read, decide, insert":

```js
// Repeatable: the unique index decides, not the application.
await checks.updateOne(
  { tenantId, domain, isoWeek },              // business identity
  { $setOnInsert: { status: 'queued', createdAt: now } },
  { upsert: true },
)
```

- Prefer set membership over append when the collection is a set: adding a tag twice must leave one tag.
- Reserve bookkeeping (rules 2-4) for effects that genuinely cannot be shaped this way.

**Anti-patterns**:
- `findOne` then `insertOne` in application code: two concurrent callers both read absent and both insert.
- Relative arithmetic on money or stock as the primary write.

## 2. The key is derived, scoped, and readable

**Principle**: An idempotency key is a deterministic function of the business identity of the effect. Anyone reading it in a log must be able to tell which operation it protects.

**How I apply it**: `{operation}:{scope}:{identity}` — for example `create-invoice:tenant_42:shopify_order_8891`. The parts are:

- **operation** — the effect, not the endpoint. Two endpoints causing one effect share a key; one endpoint causing two effects needs two.
- **scope** — the tenant or account boundary. A key without it lets one tenant collide with another.
- **identity** — the stable external or business identifier.

Nothing else goes in: no timestamps, no attempt numbers, no worker IDs, no random UUIDs, no payload hashes (the fingerprint of rule 3 is stored beside the key, not baked into it).

**Why**: Anything that varies between attempts turns two attempts into two effects, which is the exact failure the key exists to prevent.

**Adaptation**: When a client supplies the key (`Idempotency-Key` on `POST`), treat it as the identity part and still scope it to the authenticated tenant. A client-chosen key never crosses tenants.

## 3. Store the outcome against the key and replay it

**Principle**: An idempotency record holds the key, a fingerprint of the request, the state (`in_flight`, `completed`, `failed`), and — once completed — the response that was returned. A repeat of a completed key returns the stored response without re-executing.

**Why**: Returning "already exists" to a retry is a different answer than the first call gave. The caller retried because it never saw the first answer; it needs that answer, not an error.

**How I apply it**:

```text
key           create-invoice:tenant_42:shopify_order_8891
fingerprint   sha256 of the canonical request body
state         in_flight | completed | failed
result        the response body/identifier produced by the completed run
expires_at    end of the retention window (rule 8)
```

- Same key, same fingerprint, `completed` → return the stored result.
- Same key, **different** fingerprint → reject as a conflict (`409`). The caller reused a key for a different request, which is a bug on their side, and guessing which body wins would corrupt data silently.
- Canonicalize before fingerprinting (stable key order, normalized numbers) so formatting differences do not read as conflicts.

**Anti-patterns**: storing the key but not the result, so retries get `409` instead of the original answer; fingerprinting a serialized body whose field order is not stable.

## 4. Two concurrent attempts on one key produce one execution

**Principle**: Duplicate attempts frequently arrive in parallel, not in sequence. The unique constraint on the key is what serializes them; the loser of the insert race never executes.

**How I apply it**:
1. Insert the record as `in_flight`, relying on the unique index.
2. Insert succeeded → this attempt owns the execution.
3. Duplicate-key error → read the existing record: `completed` returns its result; `in_flight` means another attempt owns it, so return `409` and let the caller retry, and never wait on a lock hoping it finishes.
4. On completion, transition `in_flight → completed` with the result in the same write.

An `in_flight` record whose owner died is recovered by lease and heartbeat, not by a timeout guess — see durable ownership in [distributed-consistency.md](distributed-consistency.md).

**Anti-patterns**: checking for the key with a read before inserting; treating a duplicate-key error as a failure to report instead of a signal to read.

## 5. A failed attempt must not consume the key

**Principle**: `completed` and `attempted` are different states. A validation error, a quota rejection, or a transient provider failure leaves the operation available to retry; only a durable business effect closes the key.

**Why**: Burning identity on failure creates permanently unusable operations — a rejected request that can never be re-submitted with the same business identity, and a user with no path forward.

**How I apply it**:
- Terminal-failure records are replaceable: a retry with the same key and the same fingerprint may re-execute.
- Record `attempt` and the error classification (see [resilience.md](resilience.md)) on the record instead of deleting it, so repeated failure is observable.
- Where a unique business constraint enforces "one effect per period", make the constraint match only successful states, so a failed attempt does not consume the period.

**Anti-patterns**: marking `completed` in a `finally` block; a unique index that counts failed rows as occupying the slot.

## 6. Classify every effect by how it can be made repeat-safe

**Principle**: Not every effect can be keyed locally. Name the class before implementing the retry.

| Class | Example | Repeat-safe by |
|---|---|---|
| Naturally idempotent | set a status, upsert a projection | the shape of the write (rule 1) |
| Locally keyable | create an entity from an external ID | idempotency record + unique index (rules 2-4) |
| Provider-keyed | payment intent, refund | the provider's own idempotency key, persisted before the call |
| Observable-once | email, webhook to a third party, push notification | a durable send marker committed with the state change |

**How I apply it**: For observable-once effects, persist the intent with the business transaction and let a relay perform the send, marking it sent afterwards ([reliable-messaging.md](reliable-messaging.md)). The relay can duplicate a send after a crash, so the receiving side must tolerate it; when a duplicate is genuinely unacceptable, the send marker is checked and set conditionally in the same write that records the attempt.

For provider-keyed effects, the ambiguous-timeout rules in [distributed-consistency.md](distributed-consistency.md) apply: query by key, never blindly repeat.

## 7. A threshold crossing is an effect with its own identity

**Principle**: Side effects triggered by a condition on shared state — "warn the client at 80% of quota", "alert when the queue exceeds N", "email on first failed payment" — are one-shot effects whose identity is the crossing itself. They get a key like any other effect (rule 2), where the identity part names the business fact: `quota-warning:{tenant}:{window}:{80}`. Encoding the window in the key re-arms the warning naturally when the window rolls — no reset cron.

**Why**: Any logic shaped as `read state → if condition → act` executes the effect N times under concurrency. A client at 79% of quota sends 7 more requests, 3 simultaneous: all 3 read the counter, all 3 see ≥80% with no warning sent, all 3 send it. In-process guards don't help — the requests land on different instances. The coordination point must live where the state lives, and the claim must be atomic.

**How I apply it**:
- Claim atomically before acting; only the winner acts:

```ts
// SET NX = atomic test-and-set. Exactly one concurrent caller gets `true`.
const claimed = await redis.set(`quota-warning:${tenantId}:${window}:80`, '1',
  { NX: true, EX: windowTtlSeconds });
if (claimed) await notifier.quotaThresholdReached(tenantId, 0.8);
```

- When the state is a counter that only moves forward, the atomic increment itself identifies the crossing — the one caller whose `INCR` result satisfies `previous < threshold ≤ new` acts, no separate flag needed. If the value can move both ways (refunds, recomputation, rebuilds), the crossing can be observed more than once and the explicit claim is the guard.
- **Decide the failure side explicitly.** Claim-then-act loses the effect if the process dies in between (at-most-once); act-then-claim duplicates it (at-least-once). For advisory notifications like the 80% warning, at-most-once is correct: the hard limit at 100% still blocks ([async-workers.md](async-workers.md) rule 13) — the warning is UX, the block is enforcement. For must-deliver effects, neither bare ordering is acceptable: they are observable-once effects (rule 6) and need a durable send marker committed with the state change.
- Where the claim lives follows from that decision: a Redis `SET NX` is enough for advisory effects; must-deliver effects keep the marker in durable storage with the idempotency record (rules 2-4). Either way this state is not cache — losing it changes behavior (see [caching.md](caching.md)).

**Anti-patterns**: `GET` flag → if absent → send → `SET` flag (the race, verbatim); in-process guards (`static bool warned`) on anything served by more than one instance; a reset cron to re-arm warnings instead of encoding the window in the key; the same threshold checked both in the HTTP handler and in workers — one owner per effect.

## 8. Idempotency records have a retention window, and expiry is a decision

**Principle**: Records are kept for a documented window — long enough to cover every realistic retry, including manual replays — then removed. The window is an explicit product decision, not whatever a TTL index happened to be set to.

**How I apply it**:
- Retention outlives the longest retry chain: client retries, broker redelivery, DLQ redrive, and the operator replaying a batch days later.
- Removal is bounded and observable (TTL index or scheduled cleanup), and the collection is indexed on the expiry field.
- Effects that must never repeat, ever, do not rely on an expiring record: they need a permanent business constraint on the domain data itself.

**Why**: When a record expires, the key stops protecting anything and a late replay executes a second time. If that is unacceptable, the guarantee belongs in the schema, not in a cache with a TTL.

**Anti-patterns**: unbounded growth of the idempotency collection; a retention window shorter than the retry policy that feeds it.

## 9. Every effect ships with a repeat test

**Principle**: An effect is not idempotent because the code looks idempotent. It is idempotent because a test runs it twice and asserts one effect and the same answer.

**How I apply it**:
- Call the operation twice with the same key: assert one entity, one external call, identical responses.
- Run two attempts concurrently against the real unique constraint: assert exactly one execution and that the loser returns a defined answer.
- Crash between the effect and the completion write, then retry: assert convergence, not duplication.
- Same key with a changed body: assert the conflict.

These are the duplicate, concurrency, and crash cases of [../testing/distributed-systems.md](../testing/distributed-systems.md). A retry policy without them is a hope, not a guarantee.
