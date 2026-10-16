# Prepare stage

> First stage of the QA session. Reads the PR (body, diff, changed code) from the current repository, derives the flows to verify, finds the real API endpoints by grepping the app's own functional tests, seeds the test data those flows need over the real API (never by editing the database directly), and writes a plan plus a structured flow list for the execute stage. Everything app-specific comes from the app profile in the workspace.

# QA Prepare — from PR to a seeded, executable plan

Prepares everything the run needs to verify a PR: read the PR and the code, seed test data over the
real API, and produce a plan a non-technical reader can follow plus the structured flows
The execute stage will drive.

Runs fully autonomously. There is no one to ask. Whenever an interactive method would have asked a
question, apply the **substitution rule**:

> Take the conservative decision, keep going, and record a Pending entry with the reason.

A Pending entry is never a failure and never a silent skip. It is written to
`.qa-workspace/tests/<ref>/observations.md` and carried into the report by the execute stage.

**Target audience for the plan:** a non-technical reader. Write in English. No code jargon.

**The PR is the source of truth.** The PR body (test-plan checkboxes, Gherkin scenarios, Summary),
the diff, and the modified code are what the run verifies. Never block on, wait for, or invent
acceptance criteria from an external issue tracker. If the PR body is empty, derive the flows from
the diff and say so in the plan.

## Workspace layout

| Path | What it is |
|---|---|
| `.qa-workspace/profile/profile.yml` | App profile: URLs, auth, API mechanisms, repo paths, quirks. |
| `.qa-workspace/profile/MEMORY.md` | What previous runs learned about this app. |
| `.qa-workspace/profile/notes.md` | Free-form domain knowledge for this app. |
| `.qa-workspace/.env` | Secret values for the variables the profile names. Never printed. |
| the current repository | The application's code, checked out at the PR's branch. |
| `.qa-workspace/plans/<ref>.md` | Output: the human-readable plan. |
| `.qa-workspace/tests/<ref>/` | Output: `flows.json`, `seed-data.json`, `observations.md`. |

Secrets are read from `.qa-workspace/.env` under the variable names the profile gives. Never print
one, never write one to any other file, never put one in the plan or the report.

## Ref naming (applies to every path this stage writes)

Compute `<ref>` once, in Phase 1, as `pr<PR-number>-<branch-slug>` (e.g.
`pr123-branch-add-due-dates`), where `<branch-slug>` is derived exactly like in the login stage (the
host of the target environment URL reduced by the profile's `env.slugRule`). Use this **exact**
`<ref>` for every artifact name and for the seed-data marker — never shorten it to just the PR number
or just the branch, and never invent an ad-hoc name.

If the branch has **no open PR** (`gh pr view` finds none and the caller gave no PR number), use
`pr0` as the number, so the ref reads e.g. `pr0-branch-add-due-dates`. Record it as a Pending
observation ("no open PR; flows derived from the branch diff against `<base>`") — a run without a PR
is a diff-driven run, not a failure.

## Instructions

### Phase 0 — Load context

1. Take the target environment URL (`baseUrl`) from the invocation, or `env.defaultUrl` from the
   profile.
2. Read `.qa-workspace/profile/profile.yml`.
3. Read `.qa-workspace/profile/MEMORY.md` — accumulated endpoints, data models, test
   patterns, edge cases. On the **first run** this file does not exist yet: that is normal, treat it
   as empty and let the memory stage create it at the end. Do not stop.
4. Read `.qa-workspace/profile/notes.md` — domain knowledge that only applies to this app.

If `.qa-workspace/profile/profile.yml` does not exist, stop with a message pointing at
`profile.example.yml` (in this skill's folder): the run cannot proceed without a profile.

If `baseUrl` is missing or its host is listed under the profile's `env.forbiddenHosts` /
`env.productionHosts`, stop before doing anything else and write a report-ready error:
`error.kind: "env-unreachable"` with the detail. **Never against production: branch environments and
staging only.**

### Phase 1 — Read the PR

Get the PR from the current repository. If the `gh` CLI is available and the branch has an open PR:

```bash
gh pr view --json number,title,body,headRefName,headRefOid
```

Otherwise take the PR number/URL the caller gave, or fall back to the current branch with no body
(and say so in the plan).

Get the diff from the repository:

```bash
git diff $(git merge-base origin/{base-branch} HEAD)...HEAD
git diff --stat $(git merge-base origin/{base-branch} HEAD)...HEAD
```

The base branch comes from the profile (`repo.baseBranch`, default `main`). If the merge base cannot
be resolved, fall back to `git show --stat HEAD` and record a Pending observation saying the diff
was reduced to the head commit.

From the **body**, extract:
- **Test-plan checkboxes** (`- [ ]`) — the backbone of what the run is expected to check.
- **Gherkin scenarios**, if present — each `Scenario` is a candidate flow.
- Summary / Root cause / Solution — plain-language context for the plan.

From the **diff**, deduce what is observable via API or UI (new routes, copy changes, endpoints,
feature flags) that the test plan does not already mention. Do not read a huge diff end to end —
focus on controllers, domain logic, and test files (tests show the expected shape of a request and
response).

Note for the plan header: date, short SHA (7 chars), PR number, branch environment name.

### Phase 2 — Identify the endpoint and the auth mechanism (do not guess)

For each piece of test data the run needs, find the real endpoint instead of hitting a guessed path.

1. **Find the real endpoint by grepping the app's own functional/acceptance tests.** Guessing routes
   is expensive. The cheapest source of truth is the existing functional tests: they almost always
   call the real endpoint with the full path and the auth header already wired.

   ```bash
   grep -rn "<endpoint or command or entity name>" {repo.functionalTestsPath} \
     --include="{repo.testFileGlob}"
   ```

   `repo.functionalTestsPath` and `repo.testFileGlob` come from the profile — never hardcode a path
   here. If the controller declares a route with no visible prefix, the real prefix almost certainly
   comes from how a functional test assembles the full URL: do not derive it from the folder or the
   namespace, read the test.

2. **Identify which auth mechanism the endpoint needs** by reading the controller class. The profile's
   `api.mechanisms` table lists the app's mechanisms, the header shape of each, the secret it uses,
   and the code signal that identifies it (a base class, an interface, a characteristic
   method). They are **not interchangeable** — do not assume the endpoint uses the same mechanism as
   the last one you touched, and do not assume one credential works for two rows of the table.

3. If the endpoint needs a **session cookie**: derive the environment slug (same rule as the login stage)
   and read `.qa-workspace/sessions/<slug>.json`. If it is missing, or the request comes back
   401/403 or returns a login page, run the login stage (`stages/login.md`) for `baseUrl` and retry the request
   **once**.

4. If the endpoint needs a **token-type secret** (a PAT, an integration key), read it from
   `.qa-workspace/.env` under the variable the profile names for that mechanism. If that variable
   is absent or empty, **do not improvise a credential and do not fall back to a different
   mechanism.** Skip the seeding that needed it and record a Pending observation naming the
   mechanism and the endpoint it was for:

   ```
   Pending — cannot seed <what>: mechanism "<mechanism id>" needs secret <ENV_VAR_NAME>,
   which is not set in .qa-workspace/.env. Endpoint: <METHOD> <path>.
   ```

   Flows that depended on that data become Pending in the report, with this reason.

#### Trap: the UI can render a state that no longer matches what was saved

If a resource referenced by a dropdown or another field is deleted or archived, the UI may render
that field as "empty" or "default" simply because it can no longer find the option in the list —
while the stored backend value still points at the deleted id. **"It looks empty" is not "empty was
saved".** Whenever there is a way to read the real JSON or state (an internal detail endpoint, the
response of the save call), read it before moving on.

#### Deleting may not be recoverable

Many delete endpoints require archiving first and are then permanent, with no restore. If a resource
will be needed again, do not assume the deletion can be undone — create a new one instead.

### Phase 3 — Seed test data

From the code analysis, the PR description and the patterns in `MEMORY.md`, determine what test data
the flows need (a project with specific attributes, a team member, a task in a given state...) and
create it **via the real endpoint identified in Phase 2 — never by editing the database directly**.

Seed against the **API origin**, not the web app: if the profile sets `api.baseUrl` (the API lives on
a different port or subdomain than the web UI in dev), use that as the base; otherwise the API is
same-origin and the environment `baseUrl` is the base.

```bash
curl -s --max-time 30 -X POST "{api.baseUrl or baseUrl}{endpoint}" \
  -H "{auth header from Phase 2}" \
  -H "Content-Type: application/json" \
  -d '{"field": "value"}'
```

Where the profile points at real fixtures (`repo.fixturesPath`), start from a real fixture instead of
inventing the payload shape by hand, and change only the field(s) relevant to the scenario. Nested
payloads are easy to leave incomplete when written from scratch.

Mark everything created with a QA-identifiable name so it is easy to find and never confused with
real data. The marker comes from the profile (`seed.markerPattern`, default `"QA {ref} Test"`), with
`{ref}` expanded to the `<ref>` of this run.

Save what was created to `.qa-workspace/tests/<ref>/seed-data.json`:

```json
{
  "ref": "pr123-branch-something",
  "pr": 123,
  "environment": "https://branch-xxx.example.dev/",
  "created_at": "<ISO-8601 timestamp>",
  "created": [
    {
      "type": "task",
      "id": "abc123",
      "name": "QA pr123-branch-something Test",
      "endpoint": "POST /api/tasks",
      "details": "Task with a due date set"
    }
  ],
  "skipped": [
    { "what": "project in archived state", "reason": "mechanism service-token: secret not configured" }
  ]
}
```

If seeding fails or does not apply (backend-only refactor, config-only change), say so explicitly in
`created`/`skipped` and in the plan, and move on to Phase 4. A failed seeding is a Pending flow, not
an aborted run.

Environments do not clean themselves up: everything created here stays in the branch environment,
which is exactly why the marker matters.

### Phase 4 — Write the plan and the flows

Write two files.

**`.qa-workspace/plans/<ref>.md`** — English, human, non-technical, with these sections:

1. **What was done** — 2-3 lines in plain language, based on the PR.
2. **Environment** — the branch URL, and a note that the test credentials live in the workspace's
   `.env` (never print the password itself).
3. **Data created** — a table (type, ID, value, where to find it in the UI). If nothing was created,
   say so explicitly instead of leaving the section empty (e.g. "No specific data is needed for this
   test").
4. **Verification steps** — numbered. Happy path first (navigate, find the item by ID, verify the
   expected condition, act, verify the result), then a second group for extra checks (edge cases,
   alternative scenarios).
5. **Expected results if it works** — a short bullet list.
6. **Edge cases to check** — what to try and what to expect for each.
7. **PR checklist** — mirror the PR's own test-plan checkboxes verbatim. Never invent criteria that
   are not in the PR.

Plan quality rules:
- The whole file in English, no code snippets — only user-facing actions.
- Use the exact IDs from the seed data.
- Include the specific UI navigation path (e.g. "Projects > Active > search the seeded task by
  name").
- Base the checklist on the PR's own test-plan checkboxes.
- Include edge cases derived from the diff (null fields, empty lists, boundary values).

**`.qa-workspace/tests/<ref>/flows.json`** — the structured version the execute stage drives:

```json
{
  "ref": "pr123-branch-something",
  "baseUrl": "https://branch-xxx.example.dev/",
  "flows": [
    {
      "title": "A completed task shows its completion date",
      "origin": "pr-test-plan",
      "steps": ["Open Projects > Board", "Search QA pr123-... Test", "Open it", "Check the completion badge"],
      "expected": "The completion date of the seeded task is visible in the detail panel.",
      "seedRefs": ["abc123"],
      "automatable": true,
      "pendingReason": null
    }
  ]
}
```

Rules for the flow list:
- `origin` is exactly one of `pr-test-plan`, `gherkin`, `diff-derived` — it is the same field the
  report carries, so do not invent other values.
- Order the flows by importance: the PR's own test plan first, then Gherkin, then diff-derived.
- Cap the list at `limits.maxFlows` from the profile (default 8). Anything above the cap is emitted
  with `automatable: false` and `pendingReason: "flow budget reached"` so it still appears in the
  report as Pending instead of vanishing.
- A flow that a browser cannot cover (an external payment provider, a monitoring dashboard, an email
  inbox, 2FA, a captcha, a third-party OAuth popup, a complex file upload) is emitted with
  `automatable: false` and a `pendingReason` that states exactly what evidence a human would need to
  close it. Do not drop it and do not pretend it passed.

**Coverage — record what the flows will NOT reach.** After deriving the flow list, compare it against
the diff: which observable changes (files, symbols, behaviors touched) does no flow cover? A change is
uncovered when it altered observable product behavior and no flow reaches it — capped out of the flow
budget, un-seedable, non-automatable, or simply not derivable from the PR. Note each such area in
`observations.md` under a `## Coverage gaps` heading, in one product-language sentence each ("the
change touches the overdue-badge logic, but no flow verifies it"). Do not list pure refactors,
comments, or test-only edits — they are not observable. The execute stage reads these notes to fill the
report's `coverage` field, so be concrete: name the behavior, not the file path.

### Phase 5 — Record observations

Append to `.qa-workspace/tests/<ref>/observations.md` everything this phase learned or could not
do. The memory stage reads this file at the end of the run; this stage never edits the profile's
`MEMORY.md` itself.

```markdown
## Endpoints
- POST /api/tasks — mechanism: public-api — found in tests/functional/task/create.test.ts

## Data models
- Task requires `title` and `projectId`; `projectId` must reference an existing project.

## Test patterns
- Base URL prefix for internal routes comes from the functional test, not the controller annotation.

## Coverage gaps
- The change touches the overdue-badge logic, but no flow verifies it (out of flow budget).

## Pending / could not do
- Could not seed an archived project: mechanism "service-token" secret not configured.
```

### Phase 6 — Summary

Print a compact block to stdout:

```
QA prepared for <ref>
Plan: .qa-workspace/plans/<ref>.md
Flows: N (M automatable, K pending)
Data: .qa-workspace/tests/<ref>/seed-data.json
Environment: <baseUrl>

Next: the execute stage
```
