# knowledge

Ricardo's engineering principles, distilled as context documents for AI agents and as personal reference.

## Purpose

Each document is a self-contained "principles charter" for one area of software development. They are written to be **imported as agent context** in new projects: directive, explicit, with rules an agent must follow — not tutorials.

## How to use in a new project

In the project's `CLAUDE.md` (or equivalent agent context file), import the relevant documents:

```markdown
@<path-to-rstack>/knowledge/00-manifesto.md
@<path-to-rstack>/knowledge/domain/value-objects.md
@<path-to-rstack>/knowledge/databases/mongodb.md
```

Import only what applies to the project. `00-manifesto.md` applies always.

## Index

| Document | Covers |
|---|---|
| [00-manifesto.md](00-manifesto.md) | Cross-cutting principles, AI communication, design-reasoning checklist, and professional context |
| [architecture/hexagonal.md](architecture/hexagonal.md) | Ports & adapters, folder structure, dependency rules |
| [architecture/ddd.md](architecture/ddd.md) | Push logic to domain, aggregates, ubiquitous language, repositories |
| [architecture/cqrs.md](architecture/cqrs.md) | Command/query separation, handlers, read models |
| [architecture/event-driven.md](architecture/event-driven.md) | Domain events, decoupling via events, event content, idempotent consumers |
| [architecture/async-workers.md](architecture/async-workers.md) | Webhook ingestion, out-of-order events, workers, jobs, ExternalReference VO, reconciliation |
| [architecture/distributed-consistency.md](architecture/distributed-consistency.md) | Business idempotency, optimistic concurrency, distributed locks, leases, checkpoints, ambiguous outcomes |
| [architecture/idempotency.md](architecture/idempotency.md) | Repeat-safe writes, key anatomy, stored outcomes and replay, concurrent duplicates, threshold-triggered one-shots, failed attempts, retention, repeat tests |
| [architecture/reliable-messaging.md](architecture/reliable-messaging.md) | Queue vs pub/sub, delivery semantics, inbox/outbox, atomic publication intent, durable consumers |
| [architecture/resilience.md](architecture/resilience.md) | Error classification, retries, backoff, circuit breakers, bulkheads, rate limits, DLQ redrive |
| [architecture/sagas.md](architecture/sagas.md) | Multi-transaction workflows, orchestration, choreography, compensation, irreversible actions |
| [architecture/workflows.md](architecture/workflows.md) | Durable state machines, valid transitions, ownership, heartbeats, resumability, stale-event guards |
| [architecture/batch-imports.md](architecture/batch-imports.md) | Large imports, canonical normalization, chunking, backpressure, partial failure, tenant isolation |
| [architecture/modular-monolith.md](architecture/modular-monolith.md) | Modular monolith default, service extraction criteria, operational trade-offs |
| [architecture/legacy-migration.md](architecture/legacy-migration.md) | Parallel versions, per-entity routing, bridge markers, stop-making-it-worse |
| [architecture/observability.md](architecture/observability.md) | Correlation IDs end to end, sampled traces + 100% audit trail, tenant tagging, worker statics |
| [architecture/caching.md](architecture/caching.md) | Cache as a decorator over a port, unit-of-work memos vs Redis, keys/TTL/invalidation, degrade on failure |
| [solid.md](solid.md) | SOLID as problem-driven design, DIP vs DI, capability interfaces, provider strategies |
| [design-patterns.md](design-patterns.md) | Symptom → pattern map: builders, strategies, chains, factories, state, adapters/ACL, null object, resolvers, composite, why no singleton |
| [domain/value-objects.md](domain/value-objects.md) | Always VOs: Amount, typed IDs, self-validation, immutability, collection VOs when the group has rules |
| [domain/money-precision.md](domain/money-precision.md) | Round once, three precisions, rounding policy as domain, store as strings |
| [databases/mongodb.md](databases/mongodb.md) | Index-per-query, ESR rule, fitting queries to existing indexes, explain() |
| [databases/comparisons.md](databases/comparisons.md) | Translating my MongoDB patterns to MySQL/Postgres and other engines |
| [testing/tdd.md](testing/tdd.md) | TDD workflow, behavior over implementation, fixtures via builders |
| [testing/distributed-systems.md](testing/distributed-systems.md) | Contracts, duplicates, ordering, retries, crashes, ambiguous outcomes, partial failures |
| [testing/architecture-tests.md](testing/architecture-tests.md) | Executable architecture rules, completeness tests, incident tests, burn-down baselines |

## Document pattern

Each document is organized as a set of actionable rules. Each rule includes these elements when they add useful information; closely related elements may share a section:

1. **Principle** — the rule, stated in 2-3 sentences
2. **Why** — the reasoning, so an agent doesn't "optimize" the rule away
3. **How I apply it** — concrete patterns with code examples
4. **Anti-patterns** — what must NOT appear in code
5. **Adaptation** — how to translate the principle when the stack differs

## Maintenance

- Documents evolve: when a real project teaches a new lesson, it gets added here.
- Generic first, adapted to me second: rules are portable across stacks, examples reflect my usual stack.
