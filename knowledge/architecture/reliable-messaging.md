# Reliable Messaging — Queues, Inbox & Outbox

Messaging moves work across transaction and process boundaries. It does not remove failure; it relocates failure into delivery, acknowledgement, ordering, replay, and observability.

## 1. Choose queue or pub/sub by ownership of the effect

- **Queue / competing consumers**: one logical consumer group owns the work; several workers compete to execute it once logically. Use for jobs and commands.
- **Pub/sub**: each subscription receives the fact independently. Use when several autonomous consumers react to an event.

A producer publishes messages. A consumer receives and acknowledges them. Name consumer groups and subscriptions explicitly; “published” does not mean every intended consumer processed the message.

## 2. Delivery semantics are trade-offs

- **At-most-once**: acknowledge before or without durable processing. Work can be lost, but is not retried by the broker.
- **At-least-once**: acknowledge only after durable processing. Work is retried after failures, so duplicates are expected.
- **Exactly-once**: never claim this end to end unless every state transition and side effect shares the same transactional boundary. Broker features called exactly-once do not make an arbitrary database or HTTP side effect exactly-once.

Default to at-least-once plus durable idempotency ([distributed-consistency.md](distributed-consistency.md)).

## 3. Inbox makes consumer processing durable

Persist each received message in an inbox keyed uniquely by `(consumer, eventId)` before or as part of applying its local effect. The inbox stores payload, contract version, received time, processing state, attempts, and error context.

**Safe consumer sequence**:

1. Start a local transaction.
2. Insert the inbox record; a duplicate unique-key result means this consumer already accepted the delivery.
3. Apply the local idempotent business effect.
4. Persist any outgoing event intent in the outbox.
5. Commit.
6. Acknowledge the broker message.

If the consumer commits and dies before acknowledgement, the broker redelivers. The inbox turns that redelivery into a no-op or returns the stored outcome.

## 4. Transactional Outbox closes the publication gap

Persist the business state change and the intent to publish in one local database transaction. A relay later publishes pending outbox records and marks them delivered.

Without an outbox:

- Save then fail before publish → state changed, event lost.
- Publish then fail before save → consumers observe a fact that never committed.

The relay can publish and fail before marking delivered, so publication can be duplicated. Therefore every integration consumer remains idempotent. Outbox provides atomic publication intent, not exactly-once delivery.

## 5. Ordering is scoped, never global by default

If changes for one entity require order, include `entityId` and an origin version/sequence. Partition by `entityId` when the broker supports it, then reject versions older than the entity's stored watermark.

**Trade-off**: a hot entity becomes a hot partition. Global ordering serializes unrelated work and is almost never justified.

## 6. Contracts cross boundaries explicitly

Messages contain:

```text
event_id
event_type
contract_version
occurred_at
producer
tenant_id
correlation_id
causation_id
payload
```

- Domain events are internal model facts.
- Integration events are stable published contracts mapped at the boundary ([event-driven.md](event-driven.md)).
- Published schemas are immutable. Evolve through additive optional fields or a new version.
- Consumers tolerate unknown optional fields and reject unsupported required versions visibly.
- Do not put secrets or unnecessary personal data in events; messages are copied, retained, and replayed.

## 7. Failure belongs to the consumer that owns the effect

Classify failures and retry according to [resilience.md](resilience.md). A message that exhausts automatic retries enters a DLQ once, with the original identity and failure history. Redrive is controlled and observable; it never creates an automatic queue ↔ DLQ loop.

Reconciliation remains necessary for missing messages and external ambiguity. A broker is transport, not the source of truth.

## 8. Propagate context through every hop

Copy correlation, causation, tenant, process, event, and entity identities into message metadata and worker context ([observability.md](observability.md)). A new async hop creates a new span, not a new correlation chain.
