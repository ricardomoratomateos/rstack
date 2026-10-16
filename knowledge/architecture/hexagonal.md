# Hexagonal Architecture (Ports & Adapters)

## 1. Domain at the center, dependencies point inward

**Principle**: The domain layer imports nothing from application or infrastructure. No framework, no ORM, no HTTP types, no SDK ever appears in domain code.

**Why**: The domain is the part of the system that must survive framework migrations, database swaps, and vendor changes. Its purity is what makes it testable without infrastructure.

**How I apply it**: Dependency direction is always `infrastructure → application → domain`. A lint rule or code review must reject any import going the other way.

**Anti-patterns**:
- ORM decorators/annotations on domain entities.
- Domain entities extending framework base classes.
- `Request`/`Response` HTTP types reaching a use case signature.

## 2. Ports are defined by the inside, implemented by the outside

**Principle**: Domain and application layers declare the interfaces (ports) they need — repositories, clocks, publishers, external gateways. Infrastructure provides the adapters that implement them.

**How I apply it**:

```
domain/
  invoice/
    Invoice.ts                 # aggregate
    InvoiceRepository.ts       # PORT (interface) — lives in domain
    Amount.ts                  # value object
application/
  settle-invoice/
    SettleInvoiceCommandHandler.ts
infrastructure/
  persistence/
    MongoInvoiceRepository.ts  # ADAPTER — implements the port
  http/
    InvoiceController.ts       # driving adapter
```

**Anti-patterns**:
- Interfaces defined in infrastructure and consumed by domain (dependency inverted the wrong way).
- A "port" whose signature leaks vendor concepts (`findByMongoFilter(filter: Document)`).

**Port directions**:
- **Input/driving ports** expose application capabilities. HTTP controllers, CLI commands, and queue consumers invoke them.
- **Output/driven ports** describe what application/domain policy needs from repositories, external APIs, Redis coordination, clocks, queues, and object storage. Infrastructure implements them.

Do not create an interface merely because a class exists. A port marks a real boundary, a needed test seam, or multiple capabilities/implementations; trivial local functions stay concrete.

## 3. Standard folder structure per module / bounded context

**Principle**: Every module follows `domain/`, `application/`, `infrastructure/`. Consistency across modules matters more than local preferences.

**How I apply it**: One folder per bounded context (e.g. `billing/`, `catalog/`), each containing the three layers. Shared kernel (base VOs, event bus interfaces) lives in a small `shared/` context with the same layout.

## 4. Application orchestrates, domain decides

**Principle**: Use cases (command/query handlers) coordinate: load aggregate, call domain method, persist, publish events. Business decisions — every business `if` — live in domain objects.

**Why**: If logic sits in handlers it gets duplicated across use cases and can't be tested without the orchestration around it. See [ddd.md](ddd.md) "push to domain".

**Anti-patterns**:
- A handler that inspects aggregate state and decides (`if (invoice.status === 'draft') { ... }`) instead of asking the aggregate (`invoice.settle(...)` throwing/deciding internally).
- "Domain services" that are actually procedural scripts over anemic entities.

## 5. Constructor injection against ports

**Principle**: Dependencies enter through the constructor, typed as ports (interfaces), never as concrete implementations. No service locators, no singletons, no `new` of adapters inside use cases.

**How I apply it**:

```ts
class SettleInvoiceCommandHandler {
  constructor(
    private readonly invoices: InvoiceRepository,   // port
    private readonly events: EventBus,              // port
    private readonly clock: Clock,                  // port — never `new Date()` in domain/application
  ) {}
}
```

**Anti-patterns**:
- Importing a concrete repository inside a handler.
- Static access to time, randomness, or config from domain code — inject them as ports.

## Adaptation

- In frameworks with strong conventions (NestJS, Spring, Laravel): keep the framework at the adapter edge. Controllers, modules, and decorators are infrastructure; the domain folder stays framework-free.
- In small scripts/CLIs where full layering is overkill (see YAGNI): keep at minimum the rule "business logic in pure functions/objects, I/O at the edges".
