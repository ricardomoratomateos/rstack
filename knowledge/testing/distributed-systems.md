# Testing Distributed Behavior

Distributed correctness is behavior that must be exercised deliberately. A happy-path unit test cannot prove idempotency, recovery, ordering, or safe publication.

## 1. Keep the pyramid, add the missing failure cases

- **Many unit/domain tests**: invariants, transition rules, idempotency-key derivation, error classification, retry decisions, compensation decisions.
- **Some integration tests**: repositories, unique constraints, optimistic conditional writes, inbox/outbox transactions, broker acknowledgement, Redis lock scripts, object storage, provider adapters.
- **Contract tests**: every port implementation and provider mapping obeys the same outcomes and schema expectations.
- **Acceptance tests**: business scenarios across module boundaries with real infrastructure where the risk justifies it.
- **Few end-to-end tests**: critical deployed paths only.

Do not invert the pyramid by testing every retry through a slow deployed environment. Most state-machine and policy behavior is deterministic and cheap to test below the network.

## 2. Every distributed guarantee gets an adversarial test

At minimum, test:

- The same event delivered twice.
- Two different events requesting the same business effect.
- Events delivered out of order.
- Two workers attempting the same entity concurrently.
- An optimistic-lock conflict followed by re-read and rule reevaluation.
- A worker dying after the effect but before acknowledgement.
- A worker dying while holding a lease and a second worker reclaiming it.
- A stale owner attempting to commit after lease expiry.
- An external timeout after the provider may have succeeded.
- Transient failure followed by recovery with bounded backoff.
- Permanent and business errors not being retried.
- Rate-limit handling that respects `Retry-After`.
- Retry exhaustion and one-way movement to DLQ.
- Controlled redrive preserving event and business identities.
- Outbox relay publishing twice after crashing before its delivered marker.
- A saga step failing, then its compensation failing.
- Partial failure inside a batch while independent rows continue.
- Restart from the last confirmed chunk checkpoint.
- Producer load exceeding consumer capacity and admission control activating.
- A stale `processing` workflow being detected and recovered.
- An eventually consistent read model temporarily lagging without corrupting write-side decisions.

## 3. Put the crash at every boundary

For a multi-step operation, enumerate boundaries and inject failure before and after each durable write, publish, acknowledgement, external call, checkpoint, and lock renewal. After restart, assert one honest terminal outcome and no duplicated business effect.

Use deterministic fault injection and a fixed clock. Do not rely on sleeps, random process killing, or timing luck in the main suite.

## 4. Test doubles have distinct jobs

- **Dummy**: fills an unused parameter.
- **Stub**: returns a configured answer.
- **Spy**: records observable interaction when that interaction is the contract.
- **Mock**: asserts an expected interaction; use sparingly at true boundaries.
- **Fake**: working lightweight implementation, such as an in-memory repository or deterministic queue.

Prefer fakes for domain/application tests, but make them obey production constraints through shared contract tests. A fake that omits uniqueness, versions, or transaction behavior can make concurrency tests lie.

Avoid mock choreography tied to private call order. Assert durable state, emitted facts, returned outcomes, and observable provider calls.

## 5. Provider contracts use real shapes

Contract-test adapters with recorded, sanitized provider payloads: missing fields, partial refunds, unexpected optional data, rate-limit responses, pagination, and schema versions. Assert translation into the canonical model, typed errors, units, money, timestamps, and external references.

Run a smaller integration suite against provider sandboxes when available. Recorded fixtures prove our translation; sandbox tests detect that the provider contract changed.

## 6. Recovery tests are first-class acceptance tests

For business-critical flows, acceptance criteria include recovery, not only initial success. A test is incomplete if it proves “invoice created” but not “a duplicated webhook or worker crash still creates one invoice”.

Every production incident caused by a reusable structural shape adds a permanent regression or architecture test ([architecture-tests.md](architecture-tests.md)).
