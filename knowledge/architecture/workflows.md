# Durable Workflows & State Machines

Long-running work is a persisted state machine. Process memory, a chain of queued messages, and logs are not the source of truth for where the workflow is.

## 1. States and transitions are explicit

Model allowed transitions in one place and reject every other transition. States describe meaningful operational conditions, not incidental method names.

```text
starting → queued → processing → completed
                         ├─ retrying
                         ├─ waiting_dependency
                         ├─ external_result_unknown
                         ├─ reconciling
                         ├─ failed
                         └─ manual_review
```

Define terminal states explicitly. A terminal workflow does not resume unless a named operation such as `redrive`, `reconcile`, or `reopenForReview` creates a legal transition and an audit entry.

## 2. Current state, transition history, and logs are different

- **Current state** drives behavior and is stored on the workflow aggregate.
- **Transition history** is a durable business/operational audit of state changes, actor, reason, and time.
- **Logs** explain execution details and may be sampled, expired, or unavailable.

Never reconstruct authoritative workflow state by searching logs. Logs and traces point to the state record; they do not replace it.

## 3. Store confirmed progress

Use both only when their meaning is clear:

- `currentStep`: the step a live owner is attempting.
- `lastCompletedStep`: the last step whose effects and checkpoint are durable.

Recovery resumes after `lastCompletedStep`. A crash can leave `currentStep` naming work that never committed.

For chunked work, persist the same concept per chunk. Checkpoints advance monotonically through conditional writes.

The global workflow state and per-entity/chunk state are separate. The global state summarizes whether more work may be scheduled and whether all required units reached an acceptable terminal outcome. It never overwrites detailed row/entity outcomes, and it is derived or advanced atomically from durable unit state.

## 4. Ownership is a renewable lease

Persist `ownerId`, `heartbeatAt`, `leaseExpiresAt`, `updatedAt`, and a concurrency version. Claim work through one atomic conditional write. Heartbeats extend the lease only for the current owner. Expired ownership makes the workflow reclaimable; it does not prove the previous process stopped, so commits still need fencing/version checks ([distributed-consistency.md](distributed-consistency.md)).

Alert on workflows whose heartbeat is stale or whose state exceeds its expected duration. Recovery chooses resume, reconcile, fail, or manual review according to the last confirmed checkpoint and external ambiguity.

## 5. Old events never move state backwards

Each transition command/event carries the entity/workflow version or an origin sequence. Apply it only if it is valid from the current state and newer than the stored watermark. An old `processing` event cannot regress `completed`.

Terminal-state guards are necessary but insufficient: two non-terminal updates can still arrive out of order. Use versions, not a hand-written ranking of state names, unless the domain truly defines a total monotonic order.

## 6. Separate independent state machines

Do not compress payment, fulfillment, refund, and claim into one giant status enum. They have independent lifecycles and may progress concurrently:

```text
payment_state
fulfillment_state
refund_state
claim_state
```

The aggregate coordinates only the invariants that genuinely cross them. A user-facing status is a projection derived from these technical/domain states; it is not their shared source of truth.

## 7. Technical and user-visible states serve different readers

Technical states such as `retrying`, `reconciling`, or `external_result_unknown` drive operations. User-visible states should explain what the user can expect without exposing implementation noise. Map between them explicitly in a read model ([cqrs.md](cqrs.md)); do not make workers branch on presentation labels.

## 8. Cancellation is a workflow

Cancellation is cooperative, durable, and idempotent. Record `cancellation_requested`, stop claiming new units, let in-flight units reach a safe checkpoint, compensate where required, then enter an honest terminal state. Killing a worker or deleting queued messages is not cancellation.
