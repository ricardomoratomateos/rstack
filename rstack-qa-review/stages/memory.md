# Memory stage

> Last stage of the QA session. Folds what this run actually observed — endpoints found, data shapes, auth mechanisms that worked, navigation paths, edge cases, what went Pending and why — back into the app's accumulated memory, so the next run's plan is better. Learns only from evidence produced by this run; it asks nothing and invents nothing.

# QA Memory — close the loop from what the run observed

An interactive version of this stage would ask a human to rate the plan. There is no human in a
run, so the feedback signal is the run's own evidence: which flows were Verified, which failed and
how, which seeding worked, which endpoints and auth mechanisms turned out to be the right ones, and
which Pendings the run could not close.

**Learn only from what was observed.** Every line written here must trace back to something in
`report.json`, `seed-data.json` or `observations.md`. Never write a guess, a plan for next time, or a
generality that no evidence in this run supports. An empty section is correct when the run learned
nothing about it.

## Workspace layout

| Path | What it is |
|---|---|
| `.qa-workspace/tests/<ref>/report.json` | Flow verdicts, reasons, evidence. |
| `.qa-workspace/tests/<ref>/seed-data.json` | What was created, what was skipped and why. |
| `.qa-workspace/tests/<ref>/observations.md` | Endpoints, data models and patterns noted by the prepare stage. |
| `.qa-workspace/plans/<ref>.md`, `.qa-workspace/tests/<ref>/flows.json` | The plan that was executed. |
| `.qa-workspace/profile/MEMORY.md` | The app's accumulated memory — **this stage updates it**. |
| `.qa-workspace/tests/<ref>/memory-delta.md` | This run's delta, kept as the run's audit trail. |

## The delta is written first, then merged

Write the learnings as a delta file first (`memory-delta.md` under the run's `tests/<ref>/`
directory), then merge it section by section into the profile's `MEMORY.md`. The delta stays with
the run's artifacts: it records exactly what this run contributed, so a bad merge can always be
traced and undone. The same text goes into the report's `memoryDelta` field.

Only this stage edits `MEMORY.md`, and only at the end of a run. It never edits `profile.yml`: the
profile is configuration, and a run proposes changes to it, it does not make them.

## Instructions

### 1. Load the run

Read `.qa-workspace/tests/<ref>/report.json`, `.../seed-data.json` and `.../observations.md`. If
`report.json` does not exist there is nothing to learn from: write an empty
`memory-delta.md` with a one-line note saying the run produced no report, and stop.

Read `.qa-workspace/profile/MEMORY.md` to know what is **already** recorded. Never repeat
an entry that is already there — the delta only carries what is new or what this run corrected.

### 2. Derive the learnings

Go through each source and extract only entries backed by evidence:

**Known endpoints** — from `observations.md` and `seed-data.json`. One line per endpoint: method,
path, which auth mechanism it actually needed, and where it was found (the functional test file).
An endpoint that returned 401 under the mechanism first tried, and worked under another, is worth a
line saying so — that is exactly the mistake the next run should not repeat.

**Data models** — required fields, references between entities, shapes discovered while seeding or
while reading a response.

**Learned test patterns** — what worked: the auth mechanism per area of the app, navigation paths
that led to the right screen, the shape of a payload that the API accepted, an iframe or a wait that
had to be handled. Include the route-prefix lesson when it appeared (the real prefix came from the
functional test, not the controller annotation).

**Recurring edge cases** — from failed and clarified flows, and from anything in the diff that turned
out to matter (null fields, empty lists, boundary values). Tag each one by the area of the app it
belongs to.

**Pendings worth fixing** — from Pending reasons that are configuration problems rather than product
problems: a secret missing from `.qa-workspace/.env`, an SSO-only account, a flow no browser can
drive. These are what has to change for the next run to cover more; they belong in the memory so the
next run states them once instead of rediscovering them.

**Quirks that contradict the profile** — if the run found an iframe, a wait or a selector that the
profile's `quirks` block does not describe, or describes wrongly, record it explicitly as a proposed
profile correction. Do not edit `profile.yml`.

### 3. Record the run's own outcome

The feedback signal is the run's observed outcome, which is measurable:

```
Runs processed: <previous + 1>
Last run: <ref> — verdict <go|warn|no> — N verified / N pending / N failed / N clarified
Coverage trend: <verified+clarified> of <total> flows observed with evidence
```

`Runs processed` is read from the previous `MEMORY.md` and incremented by one. If the previous value
cannot be read, start at 1 and note it.

### 4. Write the delta

Write `.qa-workspace/tests/<ref>/memory-delta.md` with only the sections that have content:

```markdown
# Memory delta — <ref> — <ISO date>

## Known endpoints
- POST /api/tasks — mechanism: public-api — found in tests/functional/task/create.test.ts

## Data models
- Task requires `title` and a `projectId` referencing an existing project.

## Learned test patterns
- Internal routes: the real prefix comes from the functional test, not the controller annotation.

## Recurring edge cases
- [tasks] A task with no assignee renders an empty avatar slot instead of hiding it.

## Pendings worth fixing
- No value set for mechanism "service-token" in .qa-workspace/.env; archived-project seeding stays
  Pending until it is.

## Proposed profile corrections
- quirks.iframes: the reports section renders inside an iframe whose title varies with the date
  range. Not currently described in the profile.

## Run outcome
Runs processed: 12
Last run: pr123-branch-something — verdict warn — 4 verified / 2 pending / 0 failed / 0 clarified
Coverage trend: 4 of 6 flows observed with evidence
```

### 5. Merge into the profile's memory

Fold the delta into `.qa-workspace/profile/MEMORY.md`, section by section:

- Append new entries under their matching heading (create the heading if it is the first entry).
- If an entry **corrects** an existing line (an endpoint that turned out to need a different
  mechanism, a quirk described wrongly), replace that line instead of appending a contradiction.
- Replace the `Run outcome` block with the new one — it is a rolling status, not a log.
- Keep `MEMORY.md` deduplicated and skimmable: it is read at the start of every run, so every line
  must earn its place.

### 6. Attach it to the report

Set `memoryDelta` in `.qa-workspace/tests/<ref>/report.json` to the contents of the delta (or
leave it `null` if the delta is empty). Do not touch any other field of the report.

### 7. Confirm

Print:

```
Memory updated for <ref>
.qa-workspace/tests/<ref>/memory-delta.md — N learnings across M sections
Merged into .qa-workspace/profile/MEMORY.md
```
