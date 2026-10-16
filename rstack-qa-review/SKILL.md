---
name: rstack-qa-review
description: Autonomous QA of a pull request in the browser. Logs in to the branch environment, plans the flows from the PR diff, seeds real data through the real API, drives the flows with Playwright capturing evidence, delivers a verdict (go, warn or no) and remembers what it learned for the next run. Use when asked to "QA this PR", "test this PR in the browser", "verify this branch" or "run the QA review". Not for reviewing code against principles (use rstack-review) and not for debugging a reported bug (use rstack-investigate).
allowed-tools: Bash, Read, Write, Edit, Glob, Grep
---

# rstack-qa-review

One skill, four stages. The stages are plain markdown files in `stages/`, next to this file. They are not skills on their own: you load each one with Read and follow it, top to bottom, as if it were part of this file.

## Loading a stage

The harness prints this skill's base directory when it loads. A stage is `<base directory>/stages/<name>.md`. Read it in full before starting that stage.

If a stage file cannot be read, STOP and say which one. The pipeline is not usable without all four.

## Before anything else

- Everything app-specific lives in the app profile, `.qa-workspace/profile/profile.yml`, at the root of the repository under test. If it does not exist, STOP: tell the user to create it from `profile.example.yml` (in this skill's folder), and do not guess its contents.
- Strict autonomous mode: there is no one to ask. Where a person would have asked, take the conservative decision and record a Pending entry with the reason.
- Never run against production. The profile lists the forbidden hosts.

## The stages

Run them in this order. Do not start a stage until the previous one left its file.

| # | Stage | File | Gate before moving on |
|---|---|---|---|
| 1 | login | `stages/login.md` | A saved session for the target environment exists, or its status says why it could not (`sso-only`, `failed`). That is Pending, not a failure. |
| 2 | prepare | `stages/prepare.md` | `.qa-workspace/plans/<ref>.md` and `.qa-workspace/tests/<ref>/flows.json` exist. |
| 3 | execute | `stages/execute.md` | `.qa-workspace/tests/<ref>/report.json` exists, with a verdict for every flow. |
| 4 | memory | `stages/memory.md` | `.qa-workspace/tests/<ref>/memory-delta.md` exists and the profile memory was merged. |

The prepare and execute stages may re-run the login stage on their own when a session is missing or expired. That is expected.

If a gate fails, say which file is missing and why, and stop. Do not continue to the next stage with a half-made run, and do not invent the missing file.

## The rules that are not negotiable

- Nothing is Verified without direct evidence (a screenshot or a network response). What was not checked is Pending.
- A failure is never hidden and never aborts the run: record it as Failed and continue with the rest.
- No secret appears in a screenshot, a replay script, a note or the report.
- Nothing is published. No PR comment, no issue, no notification. The report is data, and the user decides what to do with it.

## Finish

Report in this form:

```
rstack-qa-review: stages 4/4 · flows: X verified, Y clarified, Z failed, W pending
Verdict: go | warn | no
Report: .qa-workspace/tests/<ref>/report.md
```

The verdict is derived from the flows, never chosen: `go` if every flow is verified or clarified, `warn` if none failed but some are pending, `no` if any failed.

If it stopped at a gate, replace the first line with how many stages completed and which gate failed. Add a short list of what is Pending and what a person would need to do to close it.
