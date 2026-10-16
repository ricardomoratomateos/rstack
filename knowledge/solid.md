# SOLID — Applied to Concrete Design Problems

SOLID names pressures that can improve changeability. It is not a mandate to create one interface per class, split trivial functions, or wrap framework code in layers. Apply each principle to a symptom and prefer the simpler valid design ([00-manifesto.md](00-manifesto.md)).

## 1. Single Responsibility — one reason to change

**Symptom**: a class changes when unrelated actors or policies change. A carrier importer parses files, maps invoices, calls an API, persists aggregates, and formats an error report.

**Principle**: separate responsibilities along real change boundaries: provider parsing/mapping in an adapter, business decisions in domain objects, orchestration in an application handler, persistence in a repository.

SRP does not mean “one method per class”. A cohesive aggregate can have many operations because they protect the same business responsibility.

## 2. Open/Closed — add a real variant without editing stable policy

**Symptom**: every new carrier adds branches to the same importer in several places.

Use a strategy or adapter per provider behind a stable capability port, selected explicitly ([design-patterns.md](design-patterns.md) rules 2 and 7). The second real variant justifies the abstraction; the first does not.

Open/Closed does not mean existing code can never change. Change the shared contract when the domain concept changes; do not preserve a wrong abstraction through flags and inheritance.

## 3. Liskov Substitution — implementations keep the contract

Anything accepted as a port implementation must honor its preconditions, outcomes, error semantics, and invariants. A fake repository that permits duplicate IDs while production rejects them is not substitutable. A carrier adapter whose `refund()` silently does nothing because that carrier lacks refunds is not substitutable either.

**Rule**: test every adapter against shared contract tests. If an implementation cannot honor the contract, the abstraction is wrong or too broad.

## 4. Interface Segregation — model capabilities

Consumers depend only on operations they use. Split provider capabilities:

```ts
interface InvoiceSource { fetchInvoices(...): Promise<...>; }
interface ClaimGateway { openClaim(...): Promise<...>; }
interface RefundGateway { refund(...): Promise<...>; }
```

Do not create `CarrierGateway` with twenty methods and make unsupported providers throw `NotSupported`. Capability discovery/selection happens at the boundary and missing required capability fails explicitly before the workflow starts.

Avoid microscopic interfaces with no boundary or consumer. Interface segregation serves differing capabilities, not line-count targets.

## 5. Dependency Inversion — policy owns the abstraction

High-level domain/application policy depends on ports that it defines. Low-level database, queue, Redis, and provider adapters implement those ports. Dependencies point toward the core ([hexagonal.md](architecture/hexagonal.md)).

**Dependency Inversion is not Dependency Injection**:

- Dependency Inversion is an architectural direction: policy does not depend on implementation details.
- Dependency Injection is a construction mechanism: dependencies are supplied from outside, usually by a container.

Injection of a concrete vendor SDK into a use case is DI without DIP. A domain-owned port instantiated through a hidden service locator may satisfy DIP in type shape but violates explicit injection.

## 6. Explain SOLID through the problem

Never justify a design with “because SOLID”. State:

```text
problem
→ restriction/change pressure
→ selected boundary or pattern
→ why it removes that pressure
→ main limitation
→ condition for evolving it
```

If no concrete pressure exists, keep the direct implementation.
