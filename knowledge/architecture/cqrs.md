# CQRS — Command / Query Separation

## 1. Commands mutate, queries read — never both

**Principle**: A command changes state and returns nothing (or at most the created ID). A query returns data and changes nothing. No operation does both.

**Why**: Mixing them couples read shapes to write models, hides side effects inside "reads", and blocks independent optimization of each path.

**Anti-patterns**:
- `getOrCreateCustomer()` — split into a query and a command.
- A query handler that "touches" a `lastSeenAt` field on the way out.

## 2. One handler per command/query, named by intention

**Principle**: Each use case is its own class: `CreateInvoiceCommandHandler`, `SearchPendingInvoicesQueryHandler`. Commands and queries are simple immutable DTOs carrying validated input.

**Why**: One-use-case-one-class keeps handlers small, makes the system's capabilities greppable, and gives each operation its own dependencies and tests.

**How I apply it**:

```
application/
  create-invoice/
    CreateInvoiceCommand.ts          # DTO: primitives in, VOs built at the boundary
    CreateInvoiceCommandHandler.ts
  search-pending-invoices/
    SearchPendingInvoicesQuery.ts
    SearchPendingInvoicesQueryHandler.ts
```

**Anti-patterns**: `InvoiceService` with 20 methods.

## 3. Queries may bypass the domain

**Principle**: The rich domain model exists to protect invariants on **writes**. Queries can skip aggregates and repositories and read optimized data directly (projections, denormalized reads, direct DB access through a thin read gateway).

**Why**: Hydrating full aggregates to render a list is wasteful and forces the write model to serve read shapes it shouldn't know about.

**How I apply it**:
- Write side: `command → handler → aggregate → repository`.
- Read side: `query → handler → read gateway → DTO` (projection tailored to the view, with proper index fit — see [databases/mongodb.md](../databases/mongodb.md)).
- Read DTOs are plain data for the consumer; they don't expose domain objects.

**Anti-patterns**: a query handler loading aggregates one by one, mapping them to DTOs in a loop.

## 4. CQRS ≠ event sourcing ≠ two databases

**Principle**: CQRS here means the **logical** separation above. Separate read stores, projections rebuilt from events, or event sourcing are independent decisions that need their own justification (scale, audit requirements). Default: one database, logical separation only.

**Why**: YAGNI ([00-manifesto.md](../00-manifesto.md)). The logical split is nearly free; the physical split buys you eventual consistency headaches and sync jobs.

**Rule for agents**: never propose a separate read database, event store, or projection infrastructure as part of "doing CQRS". Propose it only against a concrete measured need, separately.

## 5. Read models are consumer-shaped projections

**Principle**: dashboards and list screens receive DTOs designed for their queries, not serialized aggregates. A projection may denormalize invoice, provider, claim, and recovered-money fields when that makes the read simple and indexable.

Projection handlers are idempotent and version-aware. If an event is duplicated or older than the projected entity version, it produces no regression. Store enough source identity/version to prove this.

## 6. Eventual read consistency is a product behavior

When write and read models update asynchronously, document the expected lag. A command result must not pretend the projection is already current. UI states can show “processing” or read the authoritative write-side result when immediate confirmation is required.

Monitor projection lag and failed projection messages. Never use a stale read model to enforce a write-side invariant.

## 7. Projections are rebuildable when their source is replayable

If the system claims a projection can be rebuilt, provide a versioned, idempotent rebuild process with checkpoints, shadow output, validation, and atomic cutover. An incomplete event history cannot rebuild current state; in that case rebuild from an authoritative snapshot/query plus subsequent events.

Rebuild is an operational feature that needs tests and observability, not an assumed property of CQRS.
