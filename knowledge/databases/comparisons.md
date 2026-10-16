# Database Comparisons — Translating My MongoDB Patterns

## Purpose

My reference mental model is MongoDB ([mongodb.md](mongodb.md)). When a project uses MySQL, Postgres, or another engine, this document translates my patterns so the same discipline applies.

**Rule for agents**: when starting work on a non-Mongo engine, generate the concrete comparison against my Mongo patterns **before designing the schema**, and propose it to me for review.

## Equivalence table (Mongo ↔ relational B-tree engines)

| My Mongo pattern | MySQL / Postgres equivalent | Notes |
|---|---|---|
| ESR rule for compound indexes | Column order in composite B-tree indexes | Same logic: equality columns first, then the sort column, range columns last |
| `explain('executionStats')` | `EXPLAIN ANALYZE` | Same discipline: no full scans on production paths, examined/returned ratio near 1 |
| COLLSCAN (forbidden in prod) | Sequential scan / full table scan | Same rule: every production query hits an index |
| Covered query (`totalDocsExamined: 0`) | Covering index / index-only scan | Postgres: mind visibility map; MySQL InnoDB: secondary indexes include the PK |
| Index prefix rule (`{a,b}` covers `{a}`) | Leftmost prefix rule | Identical — same redundant-index audit applies |
| In-memory SORT stage (avoid) | `filesort` (MySQL) / explicit Sort node (PG) | Fix the same way: put the sort column in index order after equalities |
| Embedded document (read-together data) | Child table + join, or JSON column | Default to normalized child tables; JSON columns only for truly schemaless data — never for fields you filter/join on |
| Reference by ID between aggregates | Foreign key | FKs also give integrity enforcement Mongo doesn't — use them |
| Unbounded array anti-pattern | Unbounded child-table growth is fine | Relational engines handle this natively; the Mongo constraint disappears |
| `$lookup` on hot paths (avoid) | JOINs are native and cheap-ish | The instinct inverts: joins are normal here; denormalize only with measurements |
| `$indexStats` for unused indexes | `sys.schema_unused_indexes` (MySQL) / `pg_stat_user_indexes` | Same periodic audit |
| Upsert on `(source, tenant, externalId)` | `INSERT ... ON DUPLICATE KEY` / `ON CONFLICT` + unique constraint | The `ExternalReference` idempotency pattern translates directly |
| Aggregation pipeline | SQL (GROUP BY, window functions) | Window functions cover most `$group`/`$setWindowFields` uses |
| Schema flexibility | Migrations | Budget for a migration workflow from day one |

## What changes conceptually

- **Transactions**: multi-row/multi-table ACID is native and cheap — the "one aggregate per transaction" rule ([ddd.md](../architecture/ddd.md)) stays as a *design* rule, but the engine no longer forces it.
- **Modeling default flips**: in Mongo I model by access pattern (embed first); in relational I normalize first and denormalize only with evidence.
- **Locking/contention**: relational engines introduce lock behavior Mongo mostly hides — long transactions and hot rows become a review concern.

## What never changes

1. Fit the query to existing indexes before creating one.
2. Every production query is explain-verified.
3. Index per query shape, ESR/leftmost-prefix ordering.
4. Always project (`SELECT` only needed columns — `SELECT *` is the new "fetch whole document").
5. Repositories expose intention-revealing finders; no generic filter passthrough.
