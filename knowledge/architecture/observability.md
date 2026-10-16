# Observability — Correlation, Tracing, Logs

Monitoring tells us whether known conditions crossed thresholds. Observability gives enough structured evidence to investigate states and failures we did not predict. We need both: dashboards/monitors for detection, and correlated logs/traces/audit state for explanation.

## 1. One correlation ID from the edge, everywhere

**Principle**: A correlation ID is generated once at the outermost edge (reverse proxy / gateway), returned to the client in a response header, and propagated through **everything** the request causes:

- attached as metadata (a stamp/header) on every command/event dispatched,
- serialized with the message across queue boundaries, so async workers inherit it,
- **copied onto every domain event a handler spawns** — the fan-out keeps the ID,
- injected into every log line by a logging processor.

**The deliverable**: one query (`correlation:<id>`) returns every log line of a request, sync and async. If that query doesn't work, the correlation setup is broken.

**Anti-patterns**: minting a fresh correlation ID mid-flow (it forks the trail — the new chain no longer joins the original); propagating only on the command bus and forgetting events/queries.

## 2. Traces are sampled — critical flows need more

**Principle**: APM traces are sampled (keeping ~10% is normal; 100% is unaffordable). Two complements:

- **Force-keep markers**: a marker interface on critical operations (GDPR deletes, imports, money movements) sets manual-keep on the root span → those traces are always retained. Errors also force-keep.
- **A domain-level audit trail at 100%**: business-critical async flows (webhook processing, syncs) get a durable log *aggregate* keyed by correlation ID — status machine, per-retry entries, error records. When the sampled trace was dropped, this is what support debugs with. Traces are for performance; the domain audit trail is for "what happened to this webhook".

## 3. Tag everything with the tenant

**Principle**: Every trace and every log line carries the tenant ID. For HTTP requests it comes from the session/token context; for async messages, the message itself exposes it (a one-method interface like `getTenantId()`), so background work is attributable to a customer with no session around.

**Why**: "show me everything tenant X did/suffered" is the first question of every incident.

## 4. No process-static request context in long-lived workers

**Principle**: Workers process many messages in one process. Any request-scoped value held in a process-level static (correlation ID, tenant, user, cached context) leaks from one message to the next — logs and traces get attributed to the wrong request/tenant.

**How I apply it**: request context is derived from the message's own metadata (stamps/headers) on every message, and reset between messages. If a test needs reflection to clear a static, the design is already wrong.

## 5. Measure the queue from the message

**Principle**: Stamp dispatch time on every message and tag the handling span with `age = now - dispatchedAt`. Queue lag becomes a queryable APM dimension per bus/message type — complements the queue-depth metrics in [async-workers.md](async-workers.md) rule 14.

## 6. Identities have separate meanings

- `correlationId`: one user/business request across every sync and async consequence.
- `traceId`: one distributed trace; sampling and trace boundaries may differ from durable correlation.
- `spanId`: one timed operation inside a trace.
- `processId`: one durable import, saga, or workflow instance.
- `eventId`: one immutable message delivery identity.
- `entityId`: the domain object affected.
- `causationId`: the command/event that directly caused this event.

Propagate them in message metadata and structured logs; do not overload one field to mean all of them.

**Cardinality rule**: IDs belong in logs, trace attributes, and searchable event/audit records. Do not use per-entity, per-process, or correlation IDs as metric tags: they create unbounded cardinality and unusable cost. Metrics use bounded dimensions such as tenant tier, provider, operation, state, queue, and error class. Tenant ID is permitted in logs/traces; per-tenant metrics are created only for a bounded/intentional tenant set or via derived queries.

## 7. Logs are structured events

Every log has timestamp, level, message/event name, service/module, environment, operation, outcome, tenant context, correlation/trace fields, and typed error data where relevant. Log stable event names and fields, not prose that dashboards must parse.

Do not log secrets, credentials, raw personal data, or entire provider payloads. Store raw evidence in access-controlled durable storage and log its reference.

## 8. Measure resources, process flow, and business outcome

**Technical health**:
- CPU, memory, connection/thread/worker-pool saturation.
- HTTP latency, throughput, status/error rate, timeouts.
- Database latency/contention and provider dependency health.

**Process health**:
- Accepted and completed throughput.
- Queue depth, time in queue, oldest-message age.
- Processing and end-to-end duration.
- In-flight work, retry rate, DLQ entries/redrive outcomes.
- Stale heartbeats, expired leases, stuck processes, reconciliation backlog.
- Projection lag and import progress/failure rate.

**Business outcomes**:
- Orders processed.
- Rejections detected.
- Refunds opened and resolved.
- Value processed and reconciled.
- Success, partial-success, compensation, and manual-review rates.

Technical success without a business outcome is not enough. A healthy queue processing zero recoverable claims can still indicate a product/data problem.

## 9. Alerts are sustained and actionable

Alert on symptoms that require action: oldest-message age beyond the service objective, sustained error/timeout rate, DLQ growth, stuck workflows, exhausted provider quota, or end-to-end business throughput collapse. Use a duration/window so one transient spike does not page.

Every monitor states impact, likely owners, diagnostic dashboard/query, and first safe action. If nobody can act on an alert, turn it into a dashboard signal instead of a page.

## 10. Datadog views follow investigation paths

Build Datadog dashboards/views for:

- **Import/process**: current state, stage durations, row/chunk outcomes, retries, stale ownership, correlation links.
- **Tenant/customer**: workload, lag, errors, quotas, and affected business operations.
- **Provider**: request rate, concurrency, latency, 429/5xx, circuit state, retry/DLQ/reconciliation backlog.
- **Operational health**: services, queues, databases, worker pools, oldest work, error budgets.
- **Business results**: orders processed, rejections detected, refunds resolved, and value reconciled.

Monitors link to the relevant dashboard and logs/traces use the same bounded field names. One incident should be traceable from monitor → dashboard → process/entity → correlated logs/trace → durable audit state.
