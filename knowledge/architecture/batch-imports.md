# Batch Imports — Durable, Bounded & Resumable

Large imports are long-running distributed workflows, not oversized HTTP requests. The design must bound memory and in-flight work, preserve the original evidence, isolate tenants, and make every unit resumable.

## 0. Choose real-time, batch, or both by latency and volume

Use real-time processing when one fact needs low-latency handling and its work is bounded. Use batch when throughput, bulk source access, or large historical/reconciliation work matters more than per-item latency. A hybrid is often correct: webhooks provide the low-latency path while periodic/bulk imports reconcile missed or accumulated state. Both paths share business idempotency and the canonical model so they cannot create duplicate effects.

## 1. Accept only after durable ingestion

The API validates request metadata, streams the upload to object storage, persists an `Import` record, and only then returns `202 Accepted` with the import ID. Never load a large file fully into application memory and never return success while the only copy of the work is in a process or transient queue.

Store:

- Original immutable file in object storage, with checksum and content metadata.
- Import identity, tenant, source/provider, schema version, state, totals, timestamps, and cancellation state in the database.
- Chunk/row state, normalized references, errors, and checkpoints in durable storage.
- A traceable pointer from every result back to import, file, chunk, and source row.

## 2. Separate ingestion from processing

The canonical flow is:

```text
upload
→ store original
→ create Import
→ validate file/container
→ stream and partition
→ normalize rows
→ persist accepted data and row outcomes
→ audit
→ process by entity
→ reconcile external effects
→ finalize
```

Each arrow is an explicit, idempotent transition or step. The durable coordinator owns progress; an in-memory orchestrator may schedule work but is never the source of truth.

## 3. Stream first; chunk for recovery and parallelism

Parse the file as a stream. Group rows into bounded chunks to amortize database and queue overhead while limiting replay and memory.

Chunk size trades:

- Larger chunks improve throughput and reduce coordination overhead.
- Smaller chunks reduce memory, retry cost, lock duration, and the blast radius of failure.

Choose from measurements. Record the chosen size and why. A chunk checkpoint advances only after all durable effects for that chunk are confirmed.

## 4. Workers pull and claim atomically

Use a pull model: bounded workers claim pending/expired chunks via a conditional write and renewable lease ([workflows.md](workflows.md)). This naturally limits in-flight work and allows abandoned chunks to be reclaimed.

Each import, chunk, row, and target entity has stable identity. Reprocessing the same chunk or row converges through business idempotency keys and conditional writes. Do not hold one distributed lock for the whole import.

## 5. Partial failure is data, not an exception for the whole import

Persist a result per row:

```text
accepted | invalid | ambiguous | duplicate | processed | failed | manual_review
```

Store typed error code, safe message, source location, and whether the row can be retried. Continue independent rows when business rules allow it. Final import state distinguishes completed, completed-with-errors, failed structurally, cancelled, and manual review.

Offer a downloadable error report generated from durable row outcomes. Never require operators to scrape logs to learn which row failed.

## 6. Normalize through a canonical model

Each provider adapter maps its raw schema to a versioned canonical input model:

```text
UPS ───┐
FedEx ─┼─→ CanonicalInvoice
DHL ───┘
```

Keep raw and normalized data separate. The raw record is immutable evidence; the canonical record is our interpreted representation.

Boundary validation has two stages:

- **Syntactic**: shape, encoding, required columns, types, date formats.
- **Semantic**: currency support, unit meaning, identifier validity, cross-field rules, business constraints.

Rules:

- Required and optional fields are explicit in the schema.
- Currency, amount, unit, date, timezone, and external identifier become validated VOs at the boundary.
- Convert units and timezones once, with the original value retained for audit.
- Include tenant in every identity and uniqueness constraint.
- Version both provider mapping and canonical schema so a replay uses known semantics.
- Ambiguous mappings do not guess; they enter review with the raw evidence.

Provider adapters implement capabilities, not one fat interface that every provider pretends to support ([solid.md](../solid.md)).

## 7. Backpressure is an admission policy

A queue absorbs temporary bursts. It does not repair a permanent throughput deficit. Measure arrival rate, completion rate, backlog, and oldest-work age. When input persistently exceeds output:

- Bound in-flight chunks and per-provider calls.
- Pause or slow producers that we control.
- Reject or defer new imports before accepting data we cannot process within the stated service level.
- Apply per-tenant concurrent-import limits, file/row size limits, and quotas.
- Reserve capacity for small/critical work so a 500,000-row import cannot starve webhooks or other tenants.
- Scale workers only while downstream databases/providers and budgets have capacity.

Autoscaling from queue depth needs maximum bounds and should also consider oldest age and downstream saturation. More workers against a rate-limited provider increase contention, not throughput.

## 8. Progress is honest and monotonic

Expose totals discovered, rows validated, accepted, rejected, processed, reconciled, and terminal. Before the full stream is counted, label progress as indeterminate or stage-based; do not report a false percentage.

Update counters atomically or derive them from durable row/chunk records. User-facing progress is a read model and may be eventually consistent; completion is decided from authoritative workflow state.

## 9. Reprocessing and cancellation preserve identity

Reprocessing uses the original file, mapping version, and stable business keys. It creates an auditable attempt, not a new anonymous import that can duplicate effects. Allow selecting failed/reviewed units instead of replaying successful rows unnecessarily.

Cancellation follows [workflows.md](workflows.md): stop new claims, finish or expire in-flight leases, persist final row outcomes, and compensate irreversible external work only through explicit business actions.
