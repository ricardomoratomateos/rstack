# MongoDB — Indexing & Query Discipline

## 1. Fit first, index last

**Principle**: Before creating a new index, try to rewrite the query to use an existing index. Creating an index is the **last resort**, not the first reflex.

**Why**: Every index costs write throughput, RAM, and disk — forever. A query can often be reshaped (reordered predicates, added equality filter, changed sort) to fit what's already there.

**How I apply it**:
1. List existing indexes on the collection (`getIndexes()`).
2. Check whether reordering/reshaping the query makes it fit one (ESR, rule 2).
3. Check whether an existing index can be **extended** (replacing it) instead of adding a parallel one.
4. Only then create a new index — justified in the PR by the query it serves.

## 2. The ESR rule for compound indexes

**Principle**: Compound index keys go in the order **Equality → Sort → Range**.

```js
// Query:
db.invoices.find({ tenantId: X, status: 'pending', total: { $gte: 100 } })
           .sort({ createdAt: -1 })

// Index (E: tenantId, status | S: createdAt | R: total):
{ tenantId: 1, status: 1, createdAt: -1, total: 1 }
```

**Why**: equality prefixes narrow the scan; putting the sort field next lets Mongo read in order (no in-memory SORT stage); range fields last because everything after a range can't use the index for ordering.

## 3. Every production query is covered by an index

**Principle**: No COLLSCAN in production paths. Every query shipped must be verified with `explain()`.

**How I apply it**:
- `explain('executionStats')` on new/changed queries: expect `IXSCAN`, no `SORT` stage, and a sane `totalDocsExamined / nReturned` ratio (close to 1 is the goal).
- Watch for `totalKeysExamined >> nReturned` too — the index exists but doesn't fit the query.

**Rule for agents**: any new/modified Mongo query in a PR comes with its `explain()` verdict (which index, examined/returned ratio).

## 4. Model documents by access pattern

**Principle**: Design documents around how the data is read and written, not around relational normalization. Embed what is read together and owned together; reference by ID what is shared or unbounded.

**Anti-patterns**:
- Unbounded arrays inside documents (they grow until the document is unmovable).
- Fan-out joins via `$lookup` on hot paths — that shape wanted embedding (or a different aggregate boundary).

## 5. No redundant indexes

**Principle**: An index on `{ a: 1, b: 1 }` already serves queries on `{ a }` (prefix rule). Never create `{ a: 1 }` alongside it. Periodically audit with `$indexStats` and drop unused indexes.

## 6. Always project

**Principle**: Never fetch whole documents when only specific fields are needed. Aim for **covered queries** (all requested fields inside the index) on the hottest paths — `totalDocsExamined: 0`.

**Why**: full documents cost I/O, network, and cache space; covered queries skip touching documents entirely.

## 7. Paginated sorts need a unique tiebreaker

**Principle**: Every paginated sort ends with a unique key (`_id`) as the final sort field. Without a total order, documents that tie on the sort field (hundreds of docs sharing the same date) can come back in a different order on each execution — page N+1 duplicates or skips documents from page N.

**Why**: The engine gives no ordering guarantee among ties; this bites hardest with `$unionWith`/multi-collection reads, but applies to any paginated query.

## 8. Filter in the database, not after loading it

**Principle**: Never load every document of an owner/tenant and then filter in application code. A finder expresses its full predicate (owner, type, state) in the query so the database returns only what the caller needs.

**Why**: the cost is invisible while the collection is small and unbounded as it grows. Records that are disabled or soft-deleted are never removed, so "all the items of this account" grows with every reconnection, every token, every retry. Each call hydrates all of them, along with their embedded history, only to keep a handful.

**How I apply it**:
- Add an intention-revealing repository finder for the real predicate (`findEnabledByAccountAndClient`), rather than `findByAccount()->filter(...)`.
- Keep the tenant scope in the query itself ([ddd.md](../architecture/ddd.md)) and test isolation between two tenants with a real-Mongo integration test.
- Check the new finder against rule 3: index fit and `explain()`, noting the choice in the PR if you decide not to add an index.
- Ask for every collection that is never pruned: how big does it get for the heaviest tenant, and what does this call cost then?

**Anti-patterns**: `findAllBy…()` followed by `array_filter`/`->filter()` on a path that runs per request; hydrating full aggregates (with their change history) to read one field.

## Interaction with my architecture

- Repositories ([ddd.md](../architecture/ddd.md)) expose intention-revealing finders — each finder maps to a known, index-fitted query. No generic `find(filter)` passthrough: every query shape must be auditable.
- Read-side queries ([cqrs.md](../architecture/cqrs.md)) go through a read gateway with the same discipline: explain-verified, projected, covered where possible.

## Adaptation

Moving to MySQL/Postgres or another engine: see [comparisons.md](comparisons.md) — the discipline (fit first, explain everything, index per query shape) is identical; the mechanics translate.
