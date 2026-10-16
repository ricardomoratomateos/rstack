# Execute stage

> Second stage of the QA session. Executes the flows prepared by the prepare stage against the branch environment with Playwright, capturing evidence for every one of them (screenshots, network responses, console errors), assigns a verdict per flow (Verified / Failed / Pending / Clarified), saves a self-contained replay script per automated flow, and writes the structured run report. Produces no HTML and publishes nothing — the report is data.

# QA Execute — drive the flows and produce the report

Executes the plan end-to-end against the branch environment and writes
`.qa-workspace/tests/<ref>/report.json`.

**ABSOLUTE RULE — never invent anything.** Never mark something "Verified" without having observed it
directly (a screenshot, a network response). Anything unchecked goes as "Pending". Odd-looking
behavior that turns out correct by design goes as "Clarified", with an explanation. The counts in the
report must match the verdicts exactly.

**ABSOLUTE RULE — a "Failed" accuses the PRODUCT, never the observer.** `Failed` is the only verdict
that produces a global `no`, and a `no` means "the product does something wrong — do not merge". So
mark a flow `Failed` **only when you OBSERVED the product behaving incorrectly and captured evidence
of that wrong behavior** (a screenshot of the broken state, a 500 response, a console error thrown by
the app, values that contradict what the change promised). Failure evidence is mandatory: it is the
proof behind the `no`.

If you could **not complete the check with confidence** — you got lost, the element never appeared
after retries, a navigation timed out, you never reached the state you needed to observe, the login
was only partial — that is **not** a product failure. It is the observer failing to observe. Mark it
**Pending** with the reason (what you were trying to reach and where it broke down). Pending derives
to `warn`, never to `no`. When in doubt between `Failed` and `Pending`, choose `Pending`: an
unprovable failure must never be dressed up as a `no`.

This is the extension of the evidence discipline to the failing side. Just as a flow with no evidence
cannot be `Verified`, a flow with no evidence of wrong behavior cannot be `Failed` — a `Failed` flow
with no evidence must be downgraded to `Pending` before the report is written. The semantic call (is
this evidence of the product misbehaving, or of you getting lost?) is yours. Get it right at the
source.

| You observed… | Verdict | Why |
|---|---|---|
| Filtered the board by "Done" and tasks "In progress" appeared (screenshot) | **Failed** | Product does the wrong thing, evidenced → `no` |
| The seeded task appears twice in the "Done" column (screenshot) | **Failed** | Product does the wrong thing, evidenced → `no` |
| Save returned HTTP 500 (network capture) | **Failed** | Product broke, evidenced → `no` |
| Could not find the "Save" button after 3 snapshots / retries | **Pending** | Observer could not observe → `warn` |
| Navigation to the task detail timed out | **Pending** | Observer could not reach the state → `warn` |
| Login only partially succeeded; never reached the feature under test | **Pending** | Observer never got to observe → `warn` |
| An OAuth popup / captcha blocked the step | **Pending** | Browser cannot drive it → `warn` |

**Never against production: branch environments and staging only.**

Runs fully autonomously. There is no one to confirm the plan with and no one to hand a manual step
to. Where an interactive method would have asked, apply the **substitution rule**:

> Take the conservative decision, keep going, and record a Pending entry with the reason.

## Workspace layout

| Path | What it is |
|---|---|
| `.qa-workspace/profile/profile.yml` | App profile, including the `quirks` block (iframes, waits, dialogs). |
| `.qa-workspace/plans/<ref>.md` | The plan the prepare stage wrote. |
| `.qa-workspace/tests/<ref>/flows.json`, `.../seed-data.json` | What the prepare stage produced. |
| `.qa-workspace/sessions/<slug>.json` | The session saved by the login stage (+ `<slug>.status.json`). |
| `.qa-workspace/tests/<ref>/shots/`, `.../flows/`, `.../network/` | Evidence and replay scripts. |
| `.qa-workspace/tests/<ref>/report.json` | The run report. The only deliverable of this stage. |

`<ref>` is the one the prepare stage computed (`pr<PR-number>-<branch-slug>`). Reuse it as-is; never
shorten it and never invent a different one.

## Phase 0 — Requirements

1. `playwright-cli --version` — if it is missing, install the official Playwright CLI:
   `npm install -g @playwright/cli@latest`. Only if that install fails, write the report with
   `error.kind: "agent-error"` and stop.
2. Read `.qa-workspace/sessions/<slug>.status.json`:
   - `"status": "ok"` → continue.
   - `"status": "sso-only"` → **do not execute anything**. Emit every flow as **Pending** with that
     status's `detail` as the reason, set the global verdict to `warn`, write the report and stop.
     The application did not fail; the run could not observe it.
   - `"status": "failed"` → write the report with `error.kind: "login-failed"`, every flow Pending,
     global verdict `warn`, and stop.
   - The file does not exist → run the login stage (`stages/login.md`) for the target `baseUrl` first, then
     re-read it.
3. Check `.qa-workspace/sessions/<slug>.json` exists. If it is missing or expired (a request comes
   back as a login page or 401 instead of the expected content), run the login stage (`stages/login.md`) for `baseUrl`
   and retry once.

## Phase 1 — Load the work to execute

Read `.qa-workspace/tests/<ref>/flows.json`. If it does not exist (the session started at this
stage), rebuild the flow list by repeating Phase 1 of the prepare stage: PR body via `gh pr view` (or
from the caller), diff from the current repository, flows tagged with `origin` `pr-test-plan` /
`gherkin` / `diff-derived`. Do not block on anything external.

Note for the report header: date, short SHA, PR number, environment name.

## Phase 2 — Freeze the plan

There is no confirmation step. The plan from the prepare stage is the plan that runs, in its order, up to
`limits.maxFlows` (from the profile).

Split it once, before executing:

- **Automatable flows** (`automatable: true`) → Phase 3.
- **Non-automatable flows** (`automatable: false`) → they never execute. They go straight into the
  report as **Pending**, each with its `pendingReason` and the exact data a human would need to close
  it (which external system, which identifier to look up, what to expect). This covers external
  checks a browser cannot reach — a payment provider, a monitoring dashboard, an email inbox — and
  interactions a browser cannot drive: 2FA, captchas, third-party OAuth popups, complex file uploads.

Never mark a non-automatable flow as Verified, and never silently drop it.

## Phase 3 — Execution

```bash
playwright-cli open
playwright-cli state-load .qa-workspace/sessions/<slug>.json
playwright-cli goto {baseUrl}
playwright-cli snapshot
```

- **Expired session / redirected to login**: run the login stage (`stages/login.md`) for `baseUrl` to refresh it, then
  retry from the `goto`. If the login status is `sso-only`, it already explains why it cannot be
  automated — do not retry it in a loop.
- **Iframes**: many applications render large parts of the UI inside an iframe (the profile's
  `quirks.iframes` block documents which sections, and how the title varies). `snapshot` already
  includes the iframe's content, but with a different ref prefix than the rest of the page (e.g.
  `f4e...` instead of `e...`) — use those refs as-is with `click`/`fill`, there is no need to enter
  the iframe manually. If a selector really does not show up even then, inspect before concluding the
  element is absent:
  ```bash
  playwright-cli eval "() => document.querySelector('iframe')?.contentDocument?.body?.innerText"
  ```
- **Dialogs**: close them with `playwright-cli dialog-accept` before capturing.
- **Waits**: if the page looks blank it may still be loading — take another `snapshot` after a brief
  pause before concluding something failed. The profile's `quirks.waits` lists the known slow spots.

For each automatable flow:

1. Execute the steps (`click` / `fill` / `select` / `press` on the refs from the `snapshot`).
2. **Before capturing**, position the view over whatever demonstrates the result:
   ```bash
   playwright-cli eval "(el) => el.scrollIntoView({behavior:'instant', block:'center'})" {ref}
   ```
   If there is no specific ref, use `window.scrollTo(...)` via `eval` with no ref.
3. Capture with
   `playwright-cli screenshot --filename .qa-workspace/tests/<ref>/shots/NN-description.png`.
   Use `.png` (the format is inferred from the extension). Use `--full-page`
   only when the flow requires it; viewport by default. **1-2 screenshots per flow**: the ones that
   demonstrate the result, not every intermediate step.
4. If relevant, gather network evidence: `playwright-cli requests` lists the page's requests
   numbered; `playwright-cli request <index>` / `response-body <index>` show the one that matters.
   Save it to `.qa-workspace/tests/<ref>/network/NN-description.json`. It becomes an `evidence`
   entry of type `network`.
5. Check `playwright-cli console warning` (levels: `error`, `warning`, `info`, `debug`) — new JS
   errors during the flow are a finding even if the UI looks fine. Save them to
   `.qa-workspace/tests/<ref>/network/NN-console.txt` and attach as `console` evidence.
6. Assign a verdict: **Verified** / **Failed** / **Pending** / **Clarified**. Apply the product-fail
   vs observer-could-not rule above: `Failed` only for observed, evidenced wrong behavior of the
   product; anything you could not complete with confidence is `Pending`, never `Failed`.
7. Save a replay script at `.qa-workspace/tests/<ref>/flows/NN-flow-slug.sh` (slug = flow title,
   lowercase, hyphens) with every `playwright-cli` command actually run for this flow. Make it
   **self-contained** — its own `open` / `state-load .qa-workspace/sessions/<slug>.json` /
   `goto {baseUrl}` at the top, its own `close` at the end — so it can be re-run on its own later,
   independent of the rest of the session. Above every `click`/`fill`/`eval` line that used a ref,
   add a one-line comment with the semantic locator `playwright-cli` echoed back after that command
   (its "Ran Playwright code" output, e.g. `# getByRole('button', { name: 'Save' }).click()`).
   Snapshot refs are not guaranteed stable across separate runs, so that comment is the fallback: if
   a `click`/`fill` errors with "ref not found" on replay, run `playwright-cli snapshot` fresh (or
   `playwright-cli find "<text>"`) and locate the matching element by that role and name instead of
   the stale ref. `chmod +x` the script.
   Never write a credential into a replay script.

**On an observed product failure** (you saw the product do the wrong thing): capture a screenshot of
the wrong state plus the console error and the network evidence, mark the flow Failed, save the
replay script anyway (it reproduces the failure, which is exactly what a developer needs), and **keep
going with the rest of the flows** — do not abort the run. The evidence you capture here is the proof
behind the `no`; without it the flow must be downgraded to Pending, so capture it.

**On getting lost** (the element never appeared after retries, a snapshot never shows what you
expected, a navigation timed out, you could not reach the state you meant to check): this is **not** a
Failed. Mark it **Pending** with a reason that says what you were trying to reach and where it broke
down, attach whatever partial evidence you have, and move on. Do not turn your own inability to
observe into an accusation against the product.

**On a step that cannot be driven** (an unexpected captcha, an OAuth popup, an upload the browser
cannot complete): stop that flow, mark it **Pending** with the reason and whatever evidence was
captured up to that point, keep the partial replay script with a trailing comment saying where it
stopped, and move to the next flow. Never fabricate commands for steps that were not run.

Emit one progress line per finished flow (`Flow 3 verified — the modal shows 14 days`).

### Budget and time

If the token budget or the session's context is running out, stop executing and write the report
with what exists: every flow not yet run goes as **Pending** with `reason: "budget reached"`. A
partial report with honest Pendings is the correct outcome; an aborted run with no report is not.

## Phase 4 — Write the report

Write `.qa-workspace/tests/<ref>/report.json`.

```json
{
  "ref": "pr123-branch-something",
  "verdict": "go",
  "flows": [
    {
      "title": "A completed task shows its completion date",
      "origin": "pr-test-plan",
      "verdict": "verified",
      "steps": ["Open Projects > Board", "Search the seeded task", "Open it"],
      "reason": null,
      "evidence": [
        { "type": "screenshot", "path": "shots/01-completion-date-visible.png", "note": "Completion badge shows Mar 14" },
        { "type": "network", "path": "network/01-task-detail.json", "note": "200, completedAt present" }
      ],
      "replayScriptPath": "flows/01-completed-task-date.sh"
    }
  ],
  "coverage": {
    "note": "Every observable change is covered by at least one flow.",
    "gaps": []
  },
  "memoryDelta": null,
  "error": null
}
```

Rules:

- `verdict` per flow is one of `verified` / `failed` / `pending` / `clarified`, lowercase.
- `reason` is **mandatory** for `pending`, `failed` and `clarified`. It states what was observed or
  what is missing, in one or two factual sentences.
- Every `verified` flow has at least one `evidence` entry. **A flow with no evidence cannot be
  Verified** — it is Pending with `reason: "no observable evidence captured"`.
- Every `failed` flow has at least one `evidence` entry showing the wrong behavior. **A flow with no
  evidence cannot be Failed** — a `no` with no proof is a false `no`. Downgrade such a flow to
  Pending; if you truly observed a failure, capture the evidence.
- `evidence.path` is relative to `.qa-workspace/tests/<ref>/`.
- Evidence types are exactly `screenshot`, `network`, `console`.
- Factual tone, short sentences, no filler.

### Coverage — say what the flows did NOT check

A `go` on two thin flows for a PR that touches fifteen things is false confidence, and it gets merged
with a green light. The report must state, explicitly, what the run left unchecked. Fill `coverage`:

- `gaps` — the areas of the diff (files, symbols, behaviors touched) that **no flow covers**, each as
  one sentence in **product language**, not code jargon: "the change touches the overdue-badge logic,
  but no flow verifies it", "the billing webhook handler changed, and nothing here exercises it".
  Base this on the prepare stage's reading of the diff (its `observations.md` and `flows.json`),
  cross-referenced against the flows you actually ran. Something is a gap when the diff changed an
  observable behavior and no flow reached it — because it was out of the flow budget, could not be
  seeded, was not automatable, or simply was not derived.
- `note` — one sentence of context. When everything observable is covered, set `gaps: []` and a note
  like "Every observable change is covered by at least one flow."
- Do not list non-observable changes (pure refactors, comments, test-only edits) as gaps — they are
  not something a QA run could ever verify. Coverage is about observable product behavior.
- `coverage` is optional. If you genuinely cannot assess it, omit it (write `null`) rather than
  inventing gaps. But prefer to fill it — the gap list is one of the most valuable things the report
  carries.

### Global verdict

- `go` — every flow is `verified` or `clarified`. No failures, no pendings.
- `warn` — no failures, but there are pendings (external checks, missing evidence, a flow that could
  not be driven, a check you got lost in, budget reached, an SSO-only login). A `warn` says "nothing
  observed is wrong, but coverage is incomplete".
- `no` — any flow is `failed`, i.e. the product was OBSERVED doing something wrong, with evidence. A
  `no` is a claim about the product, never about the observer: if you could not confirm the failure,
  it is a Pending and the verdict is `warn`.

The badge is derived, never chosen: compute it from the flow verdicts and check that the counts in
the report match them exactly.

### Errors

Set `error` only when the run could not do its job at all, with `kind` one of `env-unreachable`,
`login-failed`, `budget-exceeded`, `timeout`, `agent-error`, plus a factual `detail`. A run with an
`error` still writes its flow list, with everything unexecuted as Pending.

## Phase 4b — Render a human-readable report

Alongside `report.json`, write `.qa-workspace/tests/<ref>/report.md`: the same result as something a
person actually reads, with the screenshots embedded. This is a **local render, not publishing** —
no HTML artifact, no PR comment, no external call. Structure it:

- A header (ref, date, environment, SHA) and the **verdict** with a one-line justification.
- A counts table (verified / clarified / pending / failed).
- One section per flow: title, verdict badge (✅ Verified · ✅ Clarified · ⏳ Pending · ❌ Failed),
  the `reason` when there is one, and each screenshot inline with `![note](shots/NN-....png)` using
  the relative path (the file sits in `tests/<ref>/`, so `shots/…` resolves).
- The coverage gaps, the data seeded, and a one-line pointer to the evidence and `report.json`.

Keep it factual and short — it mirrors `report.json`, it does not editorialize. A `failed` flow's
screenshot of the wrong state is the most important image in the file; lead its section with it.

## Phase 5 — Close

Print a final block to stdout:

```
QA run finished — <ref>
Verdict: <go|warn|no> · Flows: N verified / N pending / N failed / N clarified
Report: .qa-workspace/tests/<ref>/report.json · Readable: .qa-workspace/tests/<ref>/report.md
Evidence: .qa-workspace/tests/<ref>/shots/ (N files) · Replays: .qa-workspace/tests/<ref>/flows/ (N scripts)
```

This stage publishes nothing and comments nowhere. It does not build an HTML page, does not touch the
pull request, and does not change any external ticket's state. The report is data; the caller decides
what to do with it.

Then run the memory stage (`stages/memory.md`) to fold what this run observed back into the app profile.

## Rules

- Never against production: branch environments and staging only.
- Never mark Verified without evidence. Never hide a failure.
- Never write a secret into a screenshot caption, a replay script, an evidence note or the report.
- If the run is cut short, write the report with whatever exists (unrun flows as Pending) before
  stopping.
