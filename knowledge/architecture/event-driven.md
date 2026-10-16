# Event-Driven Architecture

Domain events inside the system. For **external** events (webhooks, third-party syncs) and worker/queue mechanics, see [async-workers.md](async-workers.md).

## 1. Domain events as first-class citizens

**Principle**: Every relevant aggregate mutation emits a domain event, named in past tense, in ubiquitous language: `InvoiceCreated`, `PaymentSettled`, `RefundIssued`.

**Why**: Events are immutable facts about relevant changes and the seam where modules decouple. Unless the system is explicitly event-sourced, they are not assumed to be the complete reconstructable history of every aggregate.

**How I apply it**: aggregates record events internally (`this.record(new InvoiceSettled(...))`); the handler/unit-of-work publishes them after persistence (via outbox — see [async-workers.md](async-workers.md) rule 12).

## 2. Side effects react to events — never inline

**Principle**: Notifications, projections, syncing another aggregate: all of it goes in subscribers, not in the mutating use case.

**Rule for agents**: if a command handler does two distinct business things, the second one is almost certainly a reaction to an event. Extract it into a subscriber.

**Anti-patterns**:
- A `SettleInvoice` handler that also sends an email and updates customer stats inline.
- Subscribers that mutate the same aggregate that emitted the event (that's the aggregate's own job).

## 3. Event content depends on the consumer

**Principle**: Internal domain events carry the aggregate ID plus the data of the fact itself. Integration events (crossing a context/service boundary) may carry a fuller snapshot to give consumers autonomy. **Hard rule**: an event's payload describes *what happened at that moment* — it is never treated as current state. For current state, query the source.

**Why**: Thin events couple consumers to the producer's availability and multiply reads; fat events tempt consumers to treat stale payloads as truth. The hard rule keeps both variants safe.

**Anti-patterns**:
- A consumer patching its local copy from an event payload without version/time checks (see `ExternalReference` in [async-workers.md](async-workers.md)).
- Serializing a whole aggregate into an internal domain event "to be safe".

## 4. Events are immutable and versioned

**Principle**: Once published, an event's schema never changes. Evolution happens via a new version (`InvoiceCreated.v2`) or additive optional fields. Consumers of v1 keep working until migrated.

## 5. Consumers are idempotent

**Principle**: Delivery is at-least-once. Every subscriber must produce the same result if it receives the same event twice — dedup by event ID or make the operation naturally idempotent (upsert, set-based updates).

## 6. Strong consistency inside the aggregate, eventual between aggregates

**Principle**: One transaction covers one aggregate. Cross-aggregate effects flow through events and are eventually consistent. No distributed transactions, no two-aggregate commits.

**Why**: Distributed transactions don't scale and hide coupling. Designing for eventual consistency up front forces honest invariant boundaries.

## 7. Domain events ≠ integration events

**Principle**: Domain events are internal to a bounded context and can change freely with the model. Integration events are **published contracts** between services: explicitly designed, versioned, documented. Never expose raw domain events outside the context — map them at the boundary.

## 8. Infrastructure scales with need (YAGNI)

**Principle**: Default is an in-process event bus + outbox table. A message broker (RabbitMQ, Kafka, SQS) enters only when deployment topology or scale demands it — not as a starting point.

**Rule for agents**: never scaffold broker infrastructure for a monolith. Propose it separately, against a measured need.

## 9. Event-driven means facts cross ownership boundaries

Publishing domain events only inside one process can decouple modules, but it does not by itself create a distributed event-driven architecture. Once facts cross process/context boundaries, map them to integration contracts and apply reliable messaging, inbox/outbox, retries, and observability ([reliable-messaging.md](reliable-messaging.md)).

Events state what already happened. Commands request an action. Do not disguise imperative remote calls as events named `CreateInvoiceEvent`.

## 10. Decoupling has an operational cost

Asynchrony enables independent scaling and isolates caller latency, but introduces eventual consistency, duplicates, ordering problems, contract evolution, backlog, replay, and harder debugging. Every new subscriber needs an owner, idempotency strategy, failure policy, metrics, and reconciliation story.

Use a direct call when the caller needs an immediate result and both sides belong to the same local consistency boundary. Use an event when the producer owns the fact and consumers can react independently.
