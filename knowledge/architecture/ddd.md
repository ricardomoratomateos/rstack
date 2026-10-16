# Domain-Driven Design

DDD is a tool for complex domains where language, invariants, and model boundaries reduce real ambiguity. It is not a mandatory folder structure and does not justify ceremony around simple CRUD.

## Building blocks

- **Entity**: has stable identity and changes over time.
- **Value Object**: defined by immutable value and validates a concept ([value-objects.md](../domain/value-objects.md)).
- **Aggregate**: the smallest consistency boundary that protects a set of invariants.
- **Aggregate Root**: the only entry point through which objects inside the aggregate are changed.
- **Invariant**: a business condition that must remain true after every committed operation.

## 1. Push to domain

**Principle**: Every business `if` belongs in a domain object — entity, value object, or domain service. If business logic appears in an application handler, a controller, or a mapper, it is misplaced: move it.

**Why**: Logic in the domain is discoverable (next to the data it governs), reusable across use cases, and testable without orchestration. Logic scattered in handlers duplicates and drifts.

**How I apply it**:

```ts
// BAD — application layer deciding business rules
if (invoice.status === 'draft' && invoice.total.isPositive()) {
  invoice.status = 'sent';
}

// GOOD — the aggregate decides and protects its invariants
invoice.send(); // throws InvoiceCannotBeSent if invariants don't hold
```

**Rule for agents**: when writing a business conditional outside `domain/`, stop and move it into the aggregate/VO it concerns.

## 2. Ubiquitous language

**Principle**: Code uses the business vocabulary: `Invoice`, `Settlement`, `Refund`, `Payout` — never generic technical nouns.

**Why**: The distance between how the business talks and how the code reads is where bugs and misunderstandings live.

**Rule for agents — search before naming**: before introducing any new name (class, VO, event, field, method), search the codebase for existing similar or sibling concepts and **reuse their vocabulary and naming conventions**. The existing domain language wins over a name you consider "more correct": two names for the same concept is a bug in the ubiquitous language. Only introduce a new term when the concept is genuinely new — and then flag it explicitly.

**Anti-patterns**: `InvoiceData`, `InvoiceManager`, `InvoiceHelper`, `InvoiceProcessor`, `doProcess()`, `handleStuff()`; a new `ExternalRef` next to an existing `ExternalReference`; naming something `Cancellation` when the domain already says `Voiding`.

## 3. Small aggregates, invariants inside

**Principle**: An aggregate is the smallest cluster of objects whose invariants must hold transactionally. Keep aggregates small; reference other aggregates by typed ID, never by object.

**How I apply it**:
- `Invoice` holds its `InvoiceLine`s (invariant: total = sum of lines) but references `CustomerId`, not `Customer`.
- All mutations go through aggregate methods; no public setters. Construction through named factories that enforce validity.
- As a general rule, one transaction modifies one aggregate. Cross-aggregate consistency is eventual, via events or a saga (see [event-driven.md](event-driven.md) and [sagas.md](sagas.md)). A justified local transaction may modify more than one aggregate when they truly share one consistency boundary and the storage model supports it; treat that as a signal to re-check the aggregate boundary, not as a forbidden act or a convenience default.

**Anti-patterns**:
- God aggregates loading half the database to enforce nothing.
- Modifying two aggregates in one transaction "for convenience", without identifying the invariant that requires atomicity.

## 4. Domain events for side effects

**Principle**: When something relevant happens in an aggregate, it records a domain event (`InvoiceSettled`). Reactions in other aggregates/modules subscribe to it — the mutating use case does not call them inline.

Details, content rules, and delivery semantics: [event-driven.md](event-driven.md).

## 5. Repository per aggregate

**Principle**: One repository interface per aggregate root, declared in domain, implemented in infrastructure. Repositories speak domain language and return aggregates, never persistence rows/documents.

**How I apply it**:

```ts
interface InvoiceRepository {
  byId(id: InvoiceId): Invoice | null;
  save(invoice: Invoice): void;
  searchPendingBy(customer: CustomerId): Invoice[];  // intention-revealing finders
}
```

**Anti-patterns**:
- Generic `Repository<T>` with `find(filter: any)` — leaks the persistence model and turns queries into an unauditable free-for-all (see [databases/mongodb.md](../databases/mongodb.md): every query must fit an index).
- Repositories for non-root entities.
- Returning ORM/driver objects from a repository.

## 6. Domain services and application services have different jobs

**Domain service**: represents a stateless business operation that genuinely spans domain concepts and belongs to no single entity/VO. It speaks only domain language and contains business decisions.

**Application service / command handler**: orchestrates a use case: load aggregates, invoke domain behavior, call ports, persist, and arrange publication. It owns transaction and workflow coordination, not business `if`s.

**Anti-patterns**: naming every procedural class `DomainService`; placing provider retries or persistence transactions in a domain service; moving behavior out of an aggregate merely to make the aggregate smaller.

## 7. Bounded contexts protect language and models

**Principle**: a bounded context is the boundary within which one ubiquitous language and model are consistent. `Invoice` in billing need not have the same shape or lifecycle as an invoice record in auditing.

Context relationships are explicit through a context map. Name the upstream/downstream relationship and translate through an anti-corruption layer when an external or legacy model must not define ours ([design-patterns.md](../design-patterns.md) rule 7).

**Rule for agents**: do not share aggregates across contexts. Cross by typed contract, integration event, or ID. Shared kernels stay small and contain only concepts whose joint ownership is real.

## 8. Rich domain, thin orchestration

A rich model protects its own invariants and exposes business operations. An anemic model exposes data while handlers/services decide everything around it. Prefer the rich model when the domain has meaningful rules; do not manufacture behavior on CRUD records merely to claim DDD.

## Adaptation

- With CQRS ([cqrs.md](cqrs.md)): repositories serve the **write side**. Read-side queries may bypass them.
- In codebases with anemic models: don't fight the whole codebase (see manifesto rule 4) — but new modules I own follow these rules, and I flag the divergence.
