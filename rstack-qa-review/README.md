# rstack-qa-review: how the QA pipeline works

One skill, `rstack-qa-review`, made of four stages that turn an agent into an autonomous QA engineer for a pull request. They are
**generic**: nothing in them names a specific application. Everything app-specific lives in a
per-app profile the stages read at runtime.

## The three pieces

| Piece | Where | What it provides |
|---|---|---|
| **Stages** | `stages/` | The method. How to find an endpoint, how to capture evidence, what a verdict is. Identical for every app. |
| **Profile** | `.qa-workspace/profile/` (`profile.yml` + `notes.md`) | The application. URLs, auth mechanisms, test and fixture paths, quirks, domain knowledge. Start from [`profile.example.yml`](profile.example.yml). |
| **Memory** | `.qa-workspace/profile/MEMORY.md` | What previous runs learned. Endpoints discovered, data models, patterns, recurring edge cases. Grows run by run. |

Split rule: if a sentence names a domain, a URL or a class, it does not belong in a skill; it
belongs in the profile. If it describes how to decide something, it belongs in the skill.

Secrets live in none of the three. The profile only names environment variables
(`userSecret: APP_TEST_USER`); the values live in `.qa-workspace/.env` (`chmod 600`).

## The flow of a run

```
The login stage  ──▶  the prepare stage  ──▶  the execute stage  ──▶  the memory stage
session        plan + seeded     evidence          memory
storageState   data              + verdict         merged
```

1. **login** — logs into the branch environment with Playwright and saves the session
   (`storageState`), named per environment. Sessions persist in the workspace and are reused across
   runs. If the account only supports third-party SSO, the run **comes out Pending with an
   explanation, it does not fail**: a login that could not happen is not an application failure.
2. **prepare** — reads the PR (via the `gh` CLI or the caller, diff from the current
   repository), derives the flows, finds the real endpoints **by grepping the application's own
   functional tests** (never guessing routes), identifies the auth mechanism by reading the
   controller, seeds the data through the real API (never touching the database) and writes the
   plan + `flows.json`.
3. **execute** — drives the flows with Playwright, captures evidence (screenshots, network,
   console), assigns a verdict per flow, saves a self-contained replay script per automated flow
   and writes `report.json` plus a human-readable `report.md` with the screenshots inline.
4. **memory** — writes the run's learnings as a delta and merges them into the app's
   `MEMORY.md`, so the next run's plan is better.

## The browser tool

The stages drive the browser through the official **Playwright CLI**
([microsoft/playwright-cli](https://github.com/microsoft/playwright-cli), `@playwright/cli` on
npm): a session-keeping CLI built for coding agents — accessibility snapshots with element refs,
click/fill by ref, storageState per environment — with no MCP schema overhead. The stages install
it themselves on first run (`npm install -g @playwright/cli@latest`); there is nothing to set up
by hand.

## The workspace

Everything a run reads and produces lives under `.qa-workspace/`, a hidden directory at the root
of the repository under test. The login stage bootstraps it on first run — including adding it to the
app's `.gitignore`, which is not optional: the workspace holds credentials and session cookies and
must never be committed.

```
.qa-workspace/
├── .env                       secret values for the variables the profile names (chmod 600)
├── profile/                   profile.yml, notes.md, MEMORY.md — this app's profile
├── sessions/<slug>.json       storageState per environment, reused across runs
│   └── <slug>.status.json     last login status: ok | sso-only | failed, with a reason
├── plans/<ref>.md             one human-readable plan per PR, in English, non-technical
└── tests/<ref>/               per-run artifacts:
    ├── flows.json             the structured flows the execute stage drives
    ├── seed-data.json         what was created (and what could not be, with a reason)
    ├── observations.md        endpoints and patterns seen, for the memory stage
    ├── shots/                 PNG screenshots
    ├── network/               network responses and console errors
    ├── flows/                 replay scripts, one per automated flow
    ├── report.json            the run report (machine-readable)
    ├── report.md              the same report rendered for a human, screenshots inline
    └── memory-delta.md        what this run learned (audit trail of the memory merge)
```

A run's `<ref>` is `pr<number>-<branch-slug>` and is computed exactly once, in the prepare stage.
Every stage reuses it verbatim.

## The non-negotiable rules

- **Never against production**: branch environments and staging only. The profile lists the
  forbidden hosts and the run stops before opening a browser if the target matches.
- **Never invent anything**: nothing is marked *Verified* without direct observation (a
  screenshot, a network response). Anything unchecked comes out *Pending*. Odd-looking behavior
  that turns out correct by design comes out *Clarified*, with an explanation. A flow without
  evidence cannot be *Verified*.
- **Never hide a failure**, and never abort the run because of one: capture it, mark it *Failed*
  and keep going with the rest.
- **No secret** ever appears in a screenshot, a replay script, an evidence note or the report.

## Strict autonomous mode

There is no one to ask. Wherever an interactive method would have asked a question, the
substitution rule is always the same:

> conservative decision + a *Pending* entry in the report with the reason.

The plan is the one the prepare stage produces, anything a browser cannot drive comes out *Pending*
with the exact data a human would need, and nothing is published: the report is data, and the
caller decides what to do with it. This skill generates no HTML, comment on no PR, touch no
issue tracker and send no notifications.

## Global verdict

Derived from the flows, never chosen:

- **`go`** — every flow *verified* or *clarified*.
- **`warn`** — no *failed*, but there are *pending*.
- **`no`** — any *failed*.
