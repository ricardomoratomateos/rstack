# Resilience — Retries, Isolation & Load Control

Resilience starts by deciding which failures may recover. Retrying every exception is not resilience; it amplifies outages and can duplicate irreversible effects.

## 1. Classify before handling

Every adapter translates provider/framework failures into one of four categories:

- **Transient**: timeout before connection, 502/503, temporary network failure. Retry within a bounded policy.
- **Rate-limited**: 429 or provider quota response. Respect `Retry-After` or the provider reset time.
- **Permanent**: malformed request, unsupported contract, authentication/configuration failure. Do not retry automatically.
- **Business**: valid request rejected by a domain rule, such as an already refunded amount. Return a typed outcome; do not send it to infrastructure retries.
- **Ambiguous**: the request may have succeeded but its response was lost. Reconcile before repeating the side effect ([distributed-consistency.md](distributed-consistency.md) rule 7).

Record the classification with the error so operators can understand why the system retried, stopped, reconciled, or requested review.

## 2. Retry policies are bounded and operation-specific

Use exponential backoff with jitter to spread attempts:

```text
delay = random(0, min(cap, base * 2^attempt))
```

Rules:

- Set an attempt limit and a total elapsed-time budget.
- Keep timeouts shorter than the caller's remaining deadline.
- Retry only idempotent operations or operations protected by a stable idempotency key.
- Respect `Retry-After` when it is longer than the computed delay and still within the operation's deadline.
- Do not stack uncoordinated retries at HTTP client, application, queue, and workflow layers. Define one owner and account for the total attempt multiplication.
- Preserve the same operation identity across attempts.

## 3. Timeouts bound resource use and define an outcome

Every network call has explicit connect and request/operation timeouts. Propagate an overall deadline so nested calls and retries cannot outlive the original operation budget. A timeout that occurs before sending can be transient; a timeout after bytes reached the provider creates an ambiguous outcome and follows reconciliation, not an assumed failure.

Timeouts should be shorter than leases and worker visibility deadlines, leaving time to checkpoint, release/defer safely, or renew ownership. A circuit breaker without call timeouts cannot protect threads/connections held forever.

## 4. Circuit breakers stop futile calls

A circuit breaker is scoped per provider/capability, not global:

- **Closed**: calls flow; relevant failures contribute to the threshold.
- **Open**: calls fail fast or defer without contacting the unhealthy dependency.
- **Half-open**: a small number of probes test recovery.

Close gradually after successful probes. Add jitter to probe timing so every instance does not enter half-open together. Business rejections and caller validation errors do not trip the circuit.

**Limitation**: a breaker protects our resources and the provider. It does not recover lost work; queued jobs, retries, reconciliation, or manual handling still own the outcome.

## 5. Bulkheads isolate failures

Give each external provider or critical workload its own bounded concurrency pool, queue, connection budget, and circuit state when failure isolation matters. One slow carrier must not consume every worker or database connection.

Segregate high-priority business work from bulk work. Per-tenant caps prevent one customer from starving the others ([async-workers.md](async-workers.md)).

## 6. Rate limits and concurrency limits solve different problems

- **Rate limit**: bounds starts/requests per time window, such as 100 calls per minute.
- **Concurrency limit**: bounds work simultaneously in flight, such as 10 active calls.

A provider can require both. Concurrency alone can still exceed a per-minute quota; rate alone can allow too many slow requests to occupy resources.

For distributed enforcement, store counters/state in a shared durable-enough coordination store and update atomically:

- **Token bucket** permits controlled bursts while enforcing an average rate.
- **Sliding window** gives a closer bound over any recent interval at higher storage/coordination cost.

Rate-limit state is correctness/coordination state, not disposable cache ([caching.md](caching.md) rule 12). Limits are scoped by the provider's actual quota key: tenant, API credential, endpoint, or a documented combination.

## 7. Prevent thundering herds

Use jittered retries, jittered cache expiry, bounded half-open probes, queue admission control, and single-flight for identical recomputation. Recovery should ramp up; releasing every delayed job at the same timestamp recreates the outage.

## 8. DLQ is a terminal holding area, not a retry loop

After bounded retries, move the message once to a DLQ with payload, identity, classification, attempts, timestamps, correlation, and last error.

Redrive requires:

1. Fixing or accepting the cause.
2. Selecting a bounded set of messages.
3. Preserving original event and business identities.
4. Resetting only the retry state that should restart.
5. Monitoring success, repeat failure, and business side effects.

Never automatically bounce messages between the main queue and DLQ. Permanent, ambiguous, or repeated failures go to reconciliation or manual review.
