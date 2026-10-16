# Value Objects — Always

## 1. Never primitives for business concepts

**Principle**: A business concept never travels as a bare primitive. Money is never `amount: number` — it is an `Amount` VO (value + currency, safe arithmetic, no floats for money). Same for every concept with rules.

**Why**: Primitives can't validate themselves, can't carry behavior, and get mixed up silently (`transfer(fromId, toId)` with two `string`s compiles with the arguments swapped). A float for money is a rounding bug waiting for production.

**How I apply it**:

```ts
// BAD
function applyDiscount(amount: number, percentage: number): number

// GOOD
function applyDiscount(amount: Amount, discount: Percentage): Amount

class Amount {
  private constructor(
    private readonly cents: bigint,      // minor units — never floats
    private readonly currency: Currency,
  ) {}
  static fromCents(cents: bigint, currency: Currency): Amount { ... }
  add(other: Amount): Amount { this.assertSameCurrency(other); ... }
}
```

## 2. A VO for every concept with rules

**Principle**: `Email`, `TaxId`, `Percentage`, `DateRange`, `ExternalReference` ([async-workers.md](../architecture/async-workers.md)) — and **typed IDs**: `InvoiceId`, `CustomerId`, never `string`.

**Why (typed IDs)**: they make cross-wiring a compile error and document every signature for free.

## 3. Immutable and self-validated

**Principle**: It is impossible to construct an invalid VO. Validation lives in the constructor/factory; operations return new instances, never mutate.

```ts
class Email {
  private constructor(private readonly value: string) {}
  static of(raw: string): Email {
    if (!EMAIL_REGEX.test(raw)) throw new InvalidEmail(raw);
    return new Email(raw.toLowerCase());
  }
}
```

**Consequence**: once a VO exists, no defensive re-validation anywhere downstream. If you hold an `Email`, it's valid.

## 4. Equality by value

**Principle**: Two VOs with the same content are the same value. Implement `equals()` by comparing content, never identity/reference.

## 5. Collections are VOs too

**Principle**: When a group of items carries business meaning (invariants, named operations, an "always X" rule), the collection is a value object wrapping `readonly T[]` — not a bare `T[]`. A collection without business meaning stays a plain array (YAGNI — see [00-manifesto.md](../00-manifesto.md) rule 2).

**Why**: The same reasons any VO exists — invariants enforced once at the boundary, operations that belong on the group (not duplicated at every call site), a vocabulary the domain recognizes, and protection against in-place mutation. `lines.total()` on a `Lines` VO names what the code does; `arr.map(l => l.amount).reduce((a, b) => a + b, 0)` at every call site narrates how and gets it wrong differently everywhere.

**How I apply it**:

```ts
// GOOD — a collection with rules
class InvoiceLines {
  private constructor(private readonly items: readonly InvoiceLine[]) {}
  static of(raw: readonly InvoiceLine[]): InvoiceLines {
    if (raw.length === 0) throw new EmptyInvoiceLines();
    const seen = new Set<string>();
    for (const l of raw) {
      if (seen.has(l.productId)) throw new DuplicateLine(l.productId);
      seen.add(l.productId);
    }
    return new InvoiceLines(Object.freeze([...raw]));
  }
  get total(): Amount {
    return this.items.reduce((a, l) => a.plus(l.amount), Amount.zero());
  }
  with(added: InvoiceLine): InvoiceLines { /* new immutable instance */ }
  toReadOnly(): readonly InvoiceLine[] { return this.items; }
}

// BAD — bare array, rules scattered, mutation possible
class Invoice {
  lines: InvoiceLine[] = [];                  // mutable, exposed
}
function total(invoice: Invoice): number {
  return invoice.lines.reduce((a, l) => a + l.amount, 0);   // duplicated elsewhere
}
```

- **Wrap when there's a rule**: no duplicates, no empties, totals bounded, ordering required, members must satisfy a predicate, group-level invariants (`InvoiceLines.total === sum(amount)`), named group operations. Anything past "a bag of stuff" is a candidate.
- **Don't wrap when there isn't**: `const labels: string[]` formatted once for a log line; a parameter typed `Customer[]` flowing into a generic helper; a local variable that survives 10 lines. Wrapping these is YAGNI — a class with no methods and no invariants is just a type alias with ceremony.
- **The inner array is `readonly T[]` and frozen on construction.** Expose read-only views (`toReadOnly()` or via `Symbol.iterator`). Never return the internal array directly — it is a back door for `lines.push(...)` from anywhere in the codebase.
- **Operations return new VOs, never mutate.** `with(added)` returns a new `InvoiceLines`. The aggregate's `replaceLines(...)` is the one place that calls `InvoiceLines.of(newOnes)`.
- **Domain-level traversals live on the VO** as named methods (`lines.total()`, `lines.byCategory()`, `lines.taxable()`), composed with the functional style ([00-manifesto.md](../00-manifesto.md) rule 5) — `this.items.filter(predicate)` inside the VO, not `arr.filter(predicate)` at every call site.
- **Persistence**: the repository serializes/deserializes the collection via the VO. The aggregate never sees a raw `T[]` from a DB row and the application layer never receives one from an HTTP body — adapters construct the VO at the boundary ([rule boundary](#rule-for-agents)).

**Examples that earn their VO**:
- `InvoiceLines` (no empty, no duplicate product, total = sum, immutable).
- `EmailAddresses` (no duplicates, all valid).
- `OrderHistory` (ordered by date, append-only).
- `PricedLines` (per-line price ∊ tier).
- Product categories / permission groups (composite structure — see [design-patterns.md](../design-patterns.md) rule 10).

**Anti-patterns**:
- Bare `T[]` fields on aggregates with invariants.
- Inlined `arr.filter(...).map(...).reduce(...)` at every call site instead of a named method on the VO.
- Mutating collections in place (`arr.push`, `arr.sort` without copy).
- Getters returning the internal array for callers to read-only-promise not to mutate. The type is `readonly`; the value is also frozen or copied. Trust is not a control.
- Wrapping `T[]` in a class with no invariants or methods. That's an alias, not a VO.

## 6. Rule for agents

**When a primitive crosses a domain boundary, create (or propose) the corresponding VO.** Signals to watch for:
- A function taking two same-typed primitives that mean different things.
- A primitive validated in more than one place.
- A primitive with a unit or currency implied by its name (`amountInCents`, `weightKg`, `durationMs`) — the unit belongs in a VO.

**Boundary rule**: primitives exist only at the edges (HTTP input, DB rows, external payloads). Adapters convert to VOs on the way in and back to primitives on the way out. Inside application and domain layers, only VOs travel.

**Anti-patterns**:
- `number` for money, anywhere, ever.
- "Stringly-typed" domains: statuses, currencies, country codes as free strings.
- VOs with setters, or VOs validated by an external "validator service".
