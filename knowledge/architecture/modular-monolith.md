# Modular Monolith Before Microservices

Start with a modular monolith unless extracting a service creates a concrete, measurable advantage. Process boundaries add network failure, eventual consistency, deployment coordination, distributed observability, and operational ownership; they are not a substitute for module boundaries.

## 1. Build real modules first

Organize the monolith by bounded context. Each module owns its domain, application use cases, adapters, and persistence access. Communicate through explicit APIs/events and enforce dependency rules ([hexagonal.md](hexagonal.md), [architecture-tests.md](../testing/architecture-tests.md)).

A modular monolith can use in-process transports while preserving contracts. This keeps local transactions, low latency, simple debugging, and one deployment without coupling every module's internals.

## 2. Evaluate the complete service cost

Before extraction, compare:

- Deployment and on-call complexity.
- Network latency and partial failure.
- Loss of local transactions and introduction of eventual consistency.
- Messaging, retries, idempotency, reconciliation, and contract versioning.
- Distributed logs, traces, metrics, and incident debugging.
- Independent team ownership and release cadence.
- Independent scaling and resource profile.
- Failure isolation and blast radius.
- Security/data boundaries.
- Justified need for a different technology.

“The code is large” is a reason to improve module boundaries, not by itself a reason for services.

## 3. Extract only across an existing boundary

A service candidate should have:

- A clear bounded context and ubiquitous language.
- Explicit inputs, outputs, and data ownership.
- A need for independent scaling, isolation, technology, ownership, or deployment cadence.
- A team prepared to operate it.
- A migration plan for transactions, contracts, observability, and failure recovery.

Extract one boundary at a time using a strangler approach ([legacy-migration.md](legacy-migration.md)). Keep the contract stable and route per capability/entity where needed. Do not create a distributed monolith with shared tables, synchronous call chains, and coordinated releases.

## 4. The evolution condition is explicit

For every decision to remain a monolith, record the condition that would justify extraction: measured queue isolation need, independently scaling workload, team ownership split, deploy contention, or security boundary. Revisit when that condition becomes real, not on a calendar.
