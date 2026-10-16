# Login stage

> Log into the application under test via Playwright and save a per-environment session (storageState) in the QA workspace, so the rest of the pipeline can reuse it across runs. Every application-specific detail — login path, form selectors, success/failure indicators, SSO detection — comes from the app profile, never from this stage. Use when a QA flow needs an authenticated session for the target environment and none is saved yet, or the saved one expired. The prepare stage and the execute stage invoke it automatically when they need a fresh session.

# QA Login — session management (per environment)

Logs into the target environment and persists the session **scoped to that environment**, so a QA
session that touches more than one environment never has one login overwrite another. Sessions are
saved in the workspace and survive across runs: if a valid session already exists for the
environment, the rest of the pipeline reuses it without logging in again.

Fully autonomous: this stage never asks anything. When it cannot log in, it records a
machine-readable status that the rest of the pipeline turns into Pending or Failed entries in the
report.

## Workspace layout (the same for every stage of this pipeline)

Everything lives under `.qa-workspace/` at the root of the repository under test. It holds
credentials and sessions, so it is **always git-ignored** — the bootstrap enforces this.

| Path | What it is |
|---|---|
| `.qa-workspace/.env` | Secrets: the values for the environment variables the profiles name. `chmod 600`. |
| `.qa-workspace/profile/` | The app profile: `profile.yml`, `MEMORY.md`, `notes.md`. |
| `.qa-workspace/sessions/<slug>.json` | storageState per environment, shared by every run. |
| `.qa-workspace/sessions/<slug>.status.json` | Last login status for that environment. |
| `.qa-workspace/plans/<ref>.md` | One plan per PR (written by the prepare stage). |
| `.qa-workspace/tests/<ref>/` | Per-run artifacts: flows, seeds, evidence, report. |

The workspace is local to the repository under test, so it holds exactly one profile.

Credentials live **only** in `.qa-workspace/.env`. The profile only ever names the variables
(`userSecret: APP_TEST_USER`); it never contains a value. Never print a secret's value, never write
it to any other file, never put it in the plan or the report.

### First run — bootstrap the browser tool

The browser is driven through **Playwright CLI** (`@playwright/cli`, the official
[microsoft/playwright-cli](https://github.com/microsoft/playwright-cli)). If the command is not on
the PATH, install it before anything else — never write a failure report for a tool you can mount
yourself:

```bash
command -v playwright-cli >/dev/null || npm install -g @playwright/cli@latest
```

If the first `open` fails because the browser binary is missing, the error names the exact install
command — run it and retry once. If the install itself fails (no npm, no network), stop with a
clear message naming what is missing.

### First run — bootstrap the workspace

If `.qa-workspace/` does not exist, create it and stop with a clear message instead of guessing
credentials. **Git-ignoring the workspace is part of the bootstrap, not optional**: it contains
credentials and session cookies.

```bash
mkdir -p .qa-workspace/sessions .qa-workspace/plans .qa-workspace/tests .qa-workspace/profile
grep -qxF '.qa-workspace/' .gitignore 2>/dev/null || echo '.qa-workspace/' >> .gitignore
cat > .qa-workspace/.env <<'EOF'
# Fill in the variables the app profile names (never commit this file anywhere)
APP_TEST_USER=
APP_TEST_PASS=
EOF
chmod 600 .qa-workspace/.env
```

If the repository under test is not git-tracked or has no `.gitignore`, still create the entry —
an ignored directory that ignores nothing is the failure mode to avoid.

Then print: `First run in this repository — created .qa-workspace/ (git-ignored). Fill in
.qa-workspace/.env and the profile under .qa-workspace/profile/ before retrying.` and stop.

## Instructions

### 1. Load configuration

1. Take the target environment URL (`baseUrl`) from the invocation — the branch environment the
   caller wants to test. If none is given, use `env.defaultUrl` from the profile.
2. Read `.qa-workspace/profile/profile.yml` — take the `auth` block:
   - `auth.loginPath` (e.g. `/login`)
   - `auth.credentials.userSecret` / `auth.credentials.passSecret` — the **names** of the variables
   - `auth.form.*` — optional explicit selectors
   - `auth.success` / `auth.failure` — indicators
   - `auth.sso` — detection strings
3. Read the credentials from `.qa-workspace/.env`, using the variable names the profile gives.

If either credential is absent or empty, do not guess and do not retry: write
`.qa-workspace/sessions/<slug>.status.json` with

```json
{ "status": "failed", "reason": "missing-credentials", "detail": "<which variable is empty in .qa-workspace/.env>" }
```

and stop. The caller turns this into `error.kind: "login-failed"` in the report.

### 2. Refuse to run against production

Read `env.forbiddenHosts` and `env.productionHosts` from the profile. If the host of `baseUrl`
matches any of them, or the profile declares no branch/staging pattern that this host satisfies,
**stop immediately**: write the status file with `"reason": "production-target"` and do not open a
browser.

**Never against production: branch environments and staging only.**

### 3. Determine the environment slug

- Take the host of `baseUrl`, stripped of protocol and trailing slash.
- Derive the **slug** using `env.slugRule` from the profile. The default rule:
  - the develop host → `develop`
  - a host matching the branch pattern → `branch-<name>` (keep the `branch-` prefix, it disambiguates
    from `develop`/`staging`)
  - anything else → the full host with `.` replaced by `-`
- Session file: `.qa-workspace/sessions/<slug>.json`. **Never write to a shared or generic
  filename** — that reintroduces the single-session problem this stage exists to avoid.

### 4. Open the browser and navigate to the login page

```bash
playwright-cli open {baseUrl}{auth.loginPath}
playwright-cli snapshot
```

### 5. Detect SSO before attempting a normal login

Look at the snapshot. If there is no visible email/password form — only the SSO buttons the profile
lists in `auth.sso.detectText` (e.g. "Continue with Google" / "Sign in with Google") — **stop here**.
Automating a third-party OAuth flow with Playwright runs into the provider's bot detection, so it is
not supported.

Write `.qa-workspace/sessions/<slug>.status.json`:

```json
{
  "status": "sso-only",
  "reason": "sso-only",
  "detail": "The test account requires <provider> SSO. Third-party OAuth cannot be automated. Configure a test account with native email+password login in this app profile."
}
```

and close the browser. **This is Pending, not a failure**: The execute stage marks every flow as Pending
with this explanation and the run's global verdict is `warn`. Never report a failure the application
did not actually produce.

Do not click the SSO button and do not guess its flow.

### 6. Fill the login form

If the profile provides `auth.form.emailSelector` / `passwordSelector` / `submitSelector`, use them.
Otherwise identify the fields from the snapshot by their ref IDs, using the usual heuristic:
`input[type=email]` (or the first text input in the form), `input[type=password]`, and the form's
submit button.

```bash
playwright-cli fill {email-ref} "{user}"
playwright-cli fill {password-ref} "{pass}"
playwright-cli click {submit-ref}
```

Never echo the password into the transcript, a log line or a replay script.

### 7. Verify the login succeeded

Wait for the redirect, then take a snapshot.

**Success indicators** (profile `auth.success`, with these defaults):
- the URL moved away from the login path (e.g. to `/home` or `/dashboard`)
- the page shows user-related elements (avatar, menu, company name)
- no error message is visible

**Failure indicators** (profile `auth.failure`): any of the listed texts is visible
("Invalid credentials", "Wrong password"...).

If the page still looks blank, take one more snapshot after a brief pause before concluding
anything — a slow render is not a failed login.

**If login failed**: write the status file with `"status": "failed"`,
`"reason": "invalid-credentials"` (or `"unreachable"` if the page never loaded) and the observed
error text as `detail`. Close the browser and stop. Do NOT proceed and do NOT retry in a loop.

### 8. Save the session state

```bash
playwright-cli state-save .qa-workspace/sessions/<slug>.json
```

Read the file back and confirm it contains cookies (not just `{}`). Some apps keep their token in
localStorage instead of cookies — if the file has no cookies, check
`playwright-cli localstorage-list` and include those entries in the session.

### 9. Close the browser and record success

```bash
playwright-cli close
```

Write `.qa-workspace/sessions/<slug>.status.json`:

```json
{ "status": "ok", "slug": "<slug>", "session": ".qa-workspace/sessions/<slug>.json", "url": "<baseUrl>" }
```

Print one line: `Login ok at <baseUrl> — session saved for <slug>`. Never print the credentials.

## Sessions are per environment, not shared

Each environment gets its own file under `.qa-workspace/sessions/`. Re-running this stage for the
same environment overwrites only that environment's file. This is what lets the prepare stage and
The execute stage work against more than one environment without invalidating each other's session — and
what lets a session saved today be reused by tomorrow's run without logging in again.

## Troubleshooting

- **Page doesn't load**: the environment may not be deployed yet. Record `"reason": "unreachable"` —
  the caller maps it to `error.kind: "env-unreachable"`.
- **Fields not found in the snapshot**: the login page changed. Fall back to the generic selectors of
  step 6, and record the mismatch as an observation so the memory stage can update the profile's notes.
- **Session empty after save**: see the localStorage note in step 8.
- **401/403 later while using this session**: it expired — re-run this stage for that same
  environment and retry the request once. Other environments' sessions are unaffected.
