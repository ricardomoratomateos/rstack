# Sagas — Coordinating Local Transactions

A saga coordinates one business operation across several local transactions. Each participating aggregate or service commits independently. There is no distributed rollback.

## 1. Compensation is a new business action

When a later step fails, a compensation attempts to counteract an earlier effect: release reserved inventory, issue a refund, or cancel fulfillment.

**Compensation is not rollback**:

- The original action and its consequences were observable.
- The inverse may not restore the exact previous state.
- Fees, emails, shipments, and third-party decisions can be irreversible.
- A compensation has its own identity, retries, audit trail, and failure modes.

Before starting a saga, classify every step as reversible, compensatable with loss, or irreversible. Delay irreversible actions until the latest safe point. If they cannot be delayed, define the manual or forward-recovery outcome explicitly.

## 2. Every step and compensation is idempotent

Derive a stable key from `(sagaId, stepName, direction)` and persist its result. A retry returns or converges on the same result. Never use the delivery event ID as the only protection: a step can be requested by different messages.

Compensation can also fail. Apply the same error classification, bounded retry, DLQ, reconciliation, and manual review rules as for forward work ([resilience.md](resilience.md)). A saga is not complete merely because compensation was requested.

## 3. Orchestration is the default for complex recovery

An orchestrated saga has an explicit coordinator with durable state:

```text
saga_id
business_key
state
current_step
completed_steps
compensation_state
version
updated_at
```

The coordinator decides the next command from persisted state. Participants report facts. This centralizes recovery, timeouts, visibility, and compensation ordering.

**Trade-off**: the coordinator knows the process and becomes a critical component. Keep business rules in aggregates; the coordinator owns sequence and recovery, not every domain decision.

## 4. Choreography is for short, naturally decoupled reactions

In a choreographed saga, services react to integration events and emit the next facts. It gives participants autonomy and avoids a central coordinator, but the workflow becomes distributed across subscribers.

Use choreography when the sequence is short, ownership is obvious, and failure recovery remains local. Move to orchestration when the flow has several branches, timeouts, compensation, manual states, or support needs a single place to answer “where is this operation?”.

**Anti-pattern**: a long implicit saga whose only specification is the set of subscriptions deployed across services.

## 5. Durable messaging is part of the saga

Each local transaction persists its state and outgoing intent through an outbox. Each participant consumes through an inbox. Delivery is at-least-once; steps remain idempotent. The saga coordinator itself uses optimistic concurrency so two messages cannot advance it from the same version.

The complete reliability model is:

```text
saga state machine
+ local transactions
+ outbox/inbox
+ idempotent steps and compensations
+ bounded retries and DLQ
+ reconciliation
+ manual review for unresolved outcomes
```

## 6. Make terminal outcomes honest

Terminal states distinguish at least:

- `completed`
- `compensated`
- `completed_with_exceptions`
- `compensation_failed`
- `manual_review`

Do not collapse them into `failed`. Users and operators need to know whether money moved, inventory remained reserved, or human action is still required.
