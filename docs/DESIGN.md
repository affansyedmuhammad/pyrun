# pyrun — design notes

A small Rails app that lets WindBorne people submit Python code, runs it in an isolated
sandbox for up to two minutes, stores what it printed, and lets them browse past runs.

This document is the thinking that happened before the code. The system as built is
described in [IMPLEMENTATION.md](IMPLEMENTATION.md); where the two differ, that
document describes what exists.

It It records the decisions,
the alternatives I rejected and why, the threat model, and what I would change as the
system grows. The implementation deliberately stays small; the depth lives here.

---

## 1. Requirements and scope

From the brief:

1. Login restricted to my personal email plus any `@windbornesystems.com` address.
2. A form that evaluates untrusted Python on the backend, stores its STDOUT, and allows
   runs of up to 2 minutes.
3. A way to browse the results of past runs.

From the follow-up: the login should be our own signup and login flow, not delegated to
a third party. Google sign-in is welcome later if time allows.

What I am treating as implied by "untrusted":

- The code may be hostile, not merely buggy. Infinite loops, fork bombs, memory bombs,
  disk fills, network calls to internal services, attempts to read the app's secrets,
  and attempts to escape to the host all need a real answer.
- A 2-minute run cannot happen inside an HTTP request. Execution is asynchronous.
- The app must stay usable while runs are in flight, and one user must not be able to
  starve the others.

What I am treating as implied by "restricts to these emails": the app has to prove the
person owns the address. A signup form that only checks the domain string lets anyone
type a coworker's address and walk in. Email verification is therefore part of the login
flow, not an extra.

Out of scope, noted as follow-ups: live streaming of output while a run is in progress,
cancelling a run, per-run package installation, file inputs and outputs, sharing runs
between users. Each is cheap to add on this design; none is required by the brief.

---

## 2. Assumptions and open questions

The brief invites questions. These are the ones worth a short email to Valerie, each with
the default I will build if I hear nothing:

| Question | Default I am building |
|---|---|
| Are runs private to the person who submitted them, or visible to the whole team? | Answered: private per user, plus a superuser who can browse everyone's runs (section 4.16). |
| Which Python and which libraries should the sandbox have? | Python 3.12 with the standard library plus `numpy`, pinned. Anything else is a Dockerfile change. |
| Does sandboxed code need network access? | No. The sandbox has no network at all. This is the single most important control. |
| Custom login or Google sign-in? | Answered: custom signup and login first. Google sign-in is a stretch goal, and the model is built so it slots in (section 4.14). |
| Will the reviewer sign up with a `windbornesystems.com` address and have access to that inbox? | Yes. Verification mail goes there. If not, `ALLOWED_EMAILS` takes any extra address. |
| Should the app be deployed somewhere, or is a repo plus local instructions enough? | Answered: local first until every feature works, then deployed to AWS (section 10). A `docker compose` path stays for running locally. |
| Is STDERR worth keeping alongside STDOUT? | Yes. Tracebacks live there and it costs nothing. STDOUT stays the primary artifact per the brief. |

Assumptions about the environment: one Linux host is plenty for the expected load (a
team, not the public), Docker is available wherever the worker runs, and an SMTP
account is available for sending verification and reset mail in production.

---

## 3. Architecture

```
 Browser ──HTTPS──▶ Rails web (Puma)                 no Docker access
                        │  create Run(queued), enqueue job
                        ▼
                    Database (SQLite in WAL mode; Postgres is a config swap)
                        ▲  Solid Queue polls
                        │
                    Rails worker (bin/jobs)          the only process that can talk to Docker
                        │  docker run --network none --read-only --memory ... python3 -
                        ▼                            (also delivers mail on a separate queue)
                    Sandbox container (per run, throwaway)
                        │  stdout / stderr piped back, capped, killed at 120 s
                        ▼
                    Run row updated ──▶ Turbo broadcast ──▶ show page refreshes itself
```

Three processes with different privileges:

- **web**: serves pages, authenticates users, writes `Run` rows. It never touches Docker.
- **worker**: pulls jobs from Solid Queue, launches one container per run, supervises it,
  writes results. It is the only component with Docker access. It also sends mail.
- **sandbox**: a fresh container per run, no network, read-only filesystem, unprivileged
  user, hard CPU/memory/process limits, killed at the deadline.

Why Rails 8 defaults: Solid Queue (jobs in the DB, no Redis), Solid Cable (Turbo
broadcasts, no Redis), Propshaft + importmap (no Node build), and the built-in
authentication generator. The only external dependencies beyond Ruby are Docker, which
the sandbox needs regardless, and an SMTP account in production.

Why SQLite: it is the Rails 8 default, it needs zero setup for a reviewer who clones the
repo, and it handles a team-sized internal tool comfortably in WAL mode. Nothing in the
schema or queries is SQLite-specific. Postgres is a `database.yml` change and is what I
would run on a multi-host deployment (section 12).

---

## 4. Login flow (complete)

### 4.1 Decisions

1. **Our own email and password accounts** are the primary login, as asked. Signup,
   login, email verification, password reset, logout.
2. **Email verification is mandatory** before anything past the "check your inbox" page.
   Without it the allowlist is decorative (section 1).
3. **Built on Rails 8's `bin/rails generate authentication`**, kept as generated:
   `User` with `has_secure_password`, `Session` rows, `Current`, the `Authentication`
   concern, `SessionsController`, `PasswordsController`, `PasswordsMailer`. I add
   registrations, verification, the allowlist, an identities table, tighter cookies,
   per-email rate limits, and session termination on password change.
4. **The model separates identity from credentials** so that Google sign-in, or any
   other OmniAuth provider, is an additive change later: one new row type, one new
   controller, one button. Nothing in the session layer moves (section 4.2).

Alternatives considered:

| Approach | Notes | Verdict |
|---|---|---|
| Devise | Battle-tested, but a large configuration surface for five screens, and the follow-up asked to see a custom flow. Its `omniauthable` module is also awkward to bolt on later. | No |
| **Rails 8 generator plus additions** | Small, readable, built from framework primitives (`has_secure_password`, `authenticate_by`, `generates_token_for`, `rate_limit`). Every line is mine to explain. | **Chosen** |
| Passwordless magic link | Proves ownership by construction and has no passwords to protect, but it is not the "signup and login" that was asked for. | No |
| Google OAuth only | One click for a Workspace org and no passwords, but not what was asked, and my personal address may not be a Google account. | Stretch goal, on top |

### 4.2 Model: identity, credential, external identities

```
users            one row per person. Runs and sessions belong to this.
  email_address        canonical identity. Unique, normalized (strip + downcase).
  email_verified_at    ownership proven. Set by our link today, by a verified OAuth
                       assertion later. Null means "cannot do anything yet".
  password_digest      one credential, not the identity. NULLABLE, because a person
                       who only ever signs in with Google has no password.
  name                 optional, filled from signup or from the provider

identities       zero or more external logins per user. Empty until Google is added.
  user_id, provider ("google"), uid (provider's stable subject id),
  email_at_link (audit snapshot), last_used_at
  unique (provider, uid); index (user_id)

sessions         one row per signed-in browser, however it was started.
  user_id, ip_address, user_agent, login_method ("password" | "google" | ...)
```

The invariants the code enforces, which are what make the later extension safe:

1. **A `User` row is only ever created on a path that has passed `EmailPolicy`.** Today
   that is signup. Later it is also the OAuth callback. Both call the same
   `Users::Register` service so the rule lives in one place.
2. **`email_verified_at` gates everything.** `require_verified_email` runs on every
   controller except the pending, resend, and logout actions. Whoever proves ownership
   sets the timestamp. The gate does not care how.
3. **Every login method ends in `start_new_session_for(user, method:)`.** Password login
   calls it. The OAuth callback will call it. Sessions and `Current` never know about
   providers.
4. **A user always keeps at least one login method.** `password_digest.present? ||
   identities.any?` is a model validation. Unlinking the last identity from a
   passwordless user is refused.
5. **Linking an external identity to an existing user is allowed only when the provider
   asserts a verified email equal to the user's.** If that user is still unverified, the
   provider login wins: verify the user, **clear the password, terminate all sessions**,
   then link. The password was set by someone who never proved ownership of the address,
   so it cannot be allowed to survive.
6. **Password login on a user with no password fails with the generic message.** The
   reset flow lets such a user add a password, because completing a reset proves the
   same thing signup verification does.

Why an `identities` table instead of a `google_uid` column: a column works for exactly
one provider. Every further provider is a migration and another branch in the callback.
The table is the same amount of code for one provider and zero schema work for the
next. It also gives a place to record when each identity was last used.

Why the password is not just another `identities` row: `has_secure_password` wants its
column on the model, and the password is the only credential this app verifies itself.
External identities are verified by someone else. Different things, different tables.

`has_secure_password validations: false` is used, and the validations are re-declared
explicitly: length 12 to 72 (72 is bcrypt's input limit), confirmation, `allow_nil`, and
the "at least one login method" rule above. This is the one place the generator's
defaults are loosened, and it is done so that nullable `password_digest` is a deliberate
state rather than an accident.

### 4.3 Components

| Piece | Responsibility |
|---|---|
| `User` | As above. `normalizes :email_address`. `generates_token_for :email_verification` (24 h, bound to `email_address` and `email_verified_at`, so verifying invalidates any other outstanding link). `generates_token_for :password_reset` (15 min, bound to `password_salt`, so a used link is dead). |
| `Identity` | As above. Empty table until Google is added. |
| `Session` | One row per signed-in browser. |
| `Current` | Request-scoped `Current.session` and `Current.user`. |
| `Authentication` concern | `require_authentication`, `require_verified_email`, `resume_session`, `start_new_session_for(user, method:)`, `terminate_session`, `after_authentication_url`. |
| `EmailPolicy` | Pure function `allowed?(email)`. Reads `ALLOWED_EMAILS` and `ALLOWED_EMAIL_DOMAINS`. No I/O. |
| `AdminPolicy` | Pure function `admin?(email)`. Reads `ADMIN_EMAILS`. Section 4.16. |
| `Users::Register` | The single place a `User` is created: policy check, normalization, existing-account handling. Called by signup now, by the OAuth callback later. |
| `RegistrationsController` | `new`, `create` |
| `SessionsController` | `new`, `create`, `destroy` (generated) |
| `EmailVerificationsController` | `pending`, `create` (resend), `show` (the link) |
| `PasswordsController` | `new`, `create` (request), `edit`, `update` (generated, plus session termination and verify-on-reset) |
| `UserMailer` | `email_verification`, `password_reset`, `existing_account` |

### 4.4 Routes

```
GET    /signup                        registrations#new
POST   /signup                        registrations#create
GET    /login                         sessions#new
POST   /login                         sessions#create
DELETE /logout                        sessions#destroy
GET    /verify-email                  email_verifications#pending   signed in, unverified
POST   /verify-email                  email_verifications#create    resend, rate limited
GET    /verify-email/:token           email_verifications#show      the link
GET    /passwords/new                 passwords#new
POST   /passwords                     passwords#create
GET    /passwords/:token/edit         passwords#edit
PATCH  /passwords/:token              passwords#update
GET    /up                            health check, unauthenticated

reserved for section 4.14:
POST   /auth/:provider                OmniAuth request phase
GET    /auth/:provider/callback       omniauth_sessions#create
GET    /auth/failure                  omniauth_sessions#failure
```

Everything else sits behind `require_authentication` and `require_verified_email`.

### 4.5 Signup

1. `GET /signup`: email, password, password confirmation. The requirements are stated on
   the form: a WindBorne address, at least 12 characters.
2. `POST /signup`, in order:
   - Normalize the email.
   - `EmailPolicy.allowed?`. If not: re-render with "Sign-ups are limited to
     windbornesystems.com addresses", where the domain list is interpolated from
     `EmailPolicy.allowed_domains`, so the copy is never edited when the list changes.
     This reveals the allowlist, which is the company's own domain and not a secret.
     The attempt is logged with IP.
   - Validate the password: 12 to 72 characters, confirmation matches, not equal to the
     email, and (a product decision taken after the first build) an uppercase letter, a
     lowercase letter, a number, and a special character. The form shows a live checklist
     driven by the same rules the model enforces. A HaveIBeenPwned range check is a
     one-gem addition behind a flag, off by default because it needs outbound network
     from the web process.
   - If the address already has an account: show the **same** "check your inbox" page as
     a fresh signup, and email the owner "someone tried to sign up with your address; if
     that was you, reset your password here". No second row. The page never reveals
     whether an address is registered.
   - Otherwise `Users::Register` creates the user (unverified), `start_new_session_for`,
     send the verification email, redirect to `/verify-email`.
3. The pending page says where the mail went, has a resend button (3 per 15 minutes per
   user), and a sign-out link. Every other page redirects here until verified.

Starting a session before verification is deliberate: it makes the pending page and the
resend button trivial (the user is known), and it means clicking the link finishes the
job without a second login. It is safe because the gate in invariant 2 means an
unverified session can reach nothing.

### 4.6 Email verification

1. The link is `/verify-email/:token`, valid 24 hours, single use by construction (the
   token is bound to `email_verified_at`, which changes when it is used).
2. `show` requires authentication. If the browser is not signed in, it is sent to
   `/login` with the link as the return-to target; after login the link completes. If the
   browser is signed in as a **different** user, nothing happens and the page says the
   link belongs to another account.
3. On match: set `email_verified_at`, flash, redirect to `/runs`.
4. Expired or invalid: pending page with "that link has expired" and the resend button.

Why the clicker must be signed in as that user: it closes the pre-hijack case. If
someone signs up with a coworker's address and the coworker later clicks the
unexpected verification link, a naive flow would verify an account whose password the
attacker chose. Here the coworker cannot pass the login step, so the account stays
unverified and inert. It also makes it harmless for mail scanners to follow the link.
The cost is that opening the link on a second device asks for a login first.

### 4.7 Login (password)

1. `GET /login`: email, password, "Forgot password?", "Create an account".
2. `POST /login`: `User.authenticate_by(email_address:, password:)`. This runs bcrypt
   even when no user is found, so response time does not reveal whether an address is
   registered. On failure: the generic "Try another email address or password." On
   success: `start_new_session_for(user, method: "password")`, redirect to the return-to
   path or `/runs`. An unverified user lands on the pending page via the gate.
3. Two rate limits on this action: 10 per 3 minutes per IP (the generator's default),
   and 30 per 15 minutes per email address. The per-email limit is deliberately loose:
   it is keyed on attacker-controlled input, so a tight one would let anyone lock a
   coworker out for 15 minutes. It slows credential stuffing; it is not an account lock.
4. Accepted nit: a user with no password (a future Google-only account) skips bcrypt, so
   that case answers a few milliseconds faster. Not worth a dummy hash for an internal
   tool; noted so it is a decision rather than an oversight.

### 4.8 Password reset

1. `GET /passwords/new`: email field.
2. `POST /passwords`: always show "if that address has an account, instructions are on
   their way". If a user exists, send the reset email with `/passwords/:token/edit`.
   Rate limited per IP and per email.
3. `GET /passwords/:token/edit`: the form. Bad token: back to the request form with "that
   link has expired".
4. `PATCH /passwords/:token`: same password validation as signup; set the password;
   **terminate every session for the user**, including the current one; if the user was
   unverified, set `email_verified_at` (completing a reset proves ownership); redirect to
   `/login` with "Password updated. Sign in."

The reset flow does three jobs: the obvious one, the "you already have an account"
recovery from signup, and later, "add a password to my Google-only account".

### 4.9 Logout and sessions

- `DELETE /logout` destroys the `Session` row and clears the cookie.
- Cookie: signed, `HttpOnly`, `SameSite=Lax`, `Secure` in production, **14-day expiry**
  (the generator uses `permanent`, which is 20 years; shortened).
- A fresh `Session` row and cookie value on every login, so no fixation.
- Sessions are rows, so deleting a row is real revocation. Password change deletes all of
  a user's rows.
- `resume_session` also re-checks `EmailPolicy.allowed?(Current.user.email_address)` on
  every request. It is a pure in-memory check, and it means tightening the allowlist
  logs people out immediately.

### 4.10 Failure paths

| Situation | Behaviour |
|---|---|
| Signup with a non-allowed address | Form re-renders with the allowlist message. No row. Logged with IP. |
| Signup with an address that already has an account | Same "check your inbox" page. Owner gets the "someone tried to sign up" email with a reset link. No second row. |
| Verification link opened while signed out | Redirect to `/login` with return-to; the link completes after login. |
| Verification link opened as a different user | "This link belongs to a different account." Nothing changes. |
| Verification link expired or already used | Pending page with "expired" and a resend button. |
| Login with unknown email or wrong password | Same generic message, same response time. |
| Login with correct password, unverified email | Session starts; every page redirects to pending until verified. |
| Rate limit hit | 429 page: "Too many attempts. Try again in a few minutes." |
| Reset requested for an unknown or non-allowed address | Same "if that address has an account" page. No email. |
| Reset link expired, or password already changed since | Back to the request form with "expired". |
| Session cookie for a deleted row | Signed out, cookie cleared. |
| Tampered cookie | Fails signature verification, treated as absent. |
| Mail delivery failing | Delivery jobs retry three times with backoff. Signup still succeeds; the resend button covers transient failures. If mail is down during the demo, `REQUIRE_EMAIL_VERIFICATION=false` is the escape hatch: off by default, logged loudly at boot, and shown as a banner on every page while on. |
| Employee leaves | Their address still matches the domain, so the allowlist does not help. A `pyrun:deactivate EMAIL=` task deletes their sessions and marks the user disabled. This is the one place delegated sign-in is strictly better: disabling a Workspace account revokes access automatically (section 4.14). |

### 4.11 `EmailPolicy` details

Configuration, comma-separated:

```
ALLOWED_EMAILS=me@example.com
ALLOWED_EMAIL_DOMAINS=windbornesystems.com
```

Rules:

- Trim, lowercase, then require a syntactically valid address.
- Split on the **last** `@`. Compare the domain for **exact equality** with each allowed
  domain. Never `end_with?`, which would accept `windbornesystems.com.evil.example`.
- Subdomains are not allowed unless listed. `mail.windbornesystems.com` is a different
  domain.
- Exact-match addresses are compared after the same normalization.
- Plus-addressing passes because the domain still matches, and the verification mail
  goes to the real inbox anyway.

Unit tests cover each of these, including lookalike domains and unicode in the local part.

`EmailPolicy` also exposes `allowed_domains` for copy in views and mail. Its source is
env today. If the allowlist should be managed in-app, the source becomes an
`allowed_senders` table read through the same two methods, with a short in-process
cache because the check runs on every request. No call site changes.

### 4.12 Security controls on the login flow

- **Passwords**: bcrypt through `has_secure_password`, cost 12 in production, 12-character
  minimum, 72 maximum, never logged (`filter_parameters` covers `password` and `token`).
- **Ownership**: verification before any feature; the link must be opened by the
  signed-in owner; reset terminates all sessions; provider linking rules in 4.2.
- **Enumeration**: signup, login, and reset give uniform responses; `authenticate_by`
  gives uniform timing.
- **Brute force**: per-IP and per-email rate limits on login, signup, reset, and resend.
- **Tokens**: `generates_token_for` tokens are signed, expiring, bound to a column that
  changes on use, and never stored. There is nothing in the database to steal.
- **CSRF**: Rails forgery protection on every form, including the future OAuth start.
- **Cookies**: signed, `HttpOnly`, `SameSite=Lax`, `Secure`, 14 days, server-side rows.
- **Open redirect**: the return-to path must be a relative path on this app.
- **Transport**: `force_ssl` and HSTS in production.
- **Audit**: signups, logins, failures, resets, and rejected attempts are logged with
  email and IP. Mail bodies are not logged in production.

### 4.13 Email delivery

| Environment | Delivery |
|---|---|
| development | Written to `tmp/dev_mailbox` by a tiny delivery method and shown at `/dev/mail`, an inbox in the app's own design. No SMTP, nothing to configure. |
| test | `:test` delivery, `assert_enqueued_email_with`. |
| production | SMTP from env (`SMTP_ADDRESS`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD`, `MAIL_FROM`). Zero-DNS option: a Gmail account with an app password, which delivers to any recipient at demo volume. Better if a domain is available: Postmark or Resend with SPF and DKIM set. |

Mail is sent with `deliver_later` on a `mailers` queue, separate from the `sandbox`
queue, so a slow SMTP server never blocks a request and a backlog of runs never delays
a verification link. `APP_HOST` is required so links in mail are absolute.

### 4.14 Adding Google sign-in later

This is the extension the model in 4.2 was shaped for. What gets added:

1. Gems: `omniauth-google-oauth2`, `omniauth-rails_csrf_protection`.
2. Initializer: the provider with `scope: "openid email profile"`,
   `prompt: "select_account"`, no `hd` parameter (Google's docs say not to rely on it,
   and it would hide a non-Workspace personal account), `allowed_request_methods = [:post]`.
3. Credentials: client id and secret in `config/credentials.yml.enc` or env.
4. The three reserved routes from 4.4.
5. `OmniauthSessionsController#create`, in order:
   - Require `extra.raw_info.email_verified == true`. Normalize the email.
   - `Identity.find_by(provider:, uid:)`. If found: touch `last_used_at`, done.
   - Else `User.find_by(email_address:)`. If found and verified: link. If found and
     unverified: verify, clear password, terminate sessions, link (invariant 5).
   - Else `Users::Register` with `email_verified_at: now` and no password, then link.
     The allowlist check is inside `Users::Register`, so it cannot be skipped.
   - `start_new_session_for(user, method: "google")`, redirect.
   - `failure`: redirect to `/login` with a generic message; the reason is logged, not
     shown.
6. One button on `/login`, rendered as a POST form with the CSRF token and
   `data-turbo="false"` (the response redirects to another origin, which Turbo cannot
   follow).
7. Optional settings page: link Google to my account, unlink (refused if it would be
   the last login method), set a password (reuses the reset flow).
8. Tests with OmniAuth test mode: new user, existing verified user links, existing
   unverified user is claimed, disallowed domain rejected, unverified Google email
   rejected, `state` mismatch goes to failure.

What does not change: `Session`, `Current`, the `Authentication` concern,
`EmailPolicy`, the verification gate, runs, or any existing test. Roughly an hour of
work plus ten minutes in the Google Cloud console for the OAuth client and redirect
URIs.

### 4.15 Tests for the login flow

Controller and system tests:

- Signup with an allowed domain creates an unverified user and a session, enqueues the
  verification mail, lands on pending.
- Signup with the allowed personal address works.
- Signup with a disallowed or lookalike domain creates nothing.
- Signup with a registered address shows the same page, creates nothing, enqueues the
  "existing account" mail.
- Password shorter than 12 characters, or equal to the email, is rejected.
- Verification link verifies when opened by the owner, redirects to login when signed
  out and completes after login, does nothing for another user, fails when expired,
  fails a second time.
- Unverified user cannot reach `/runs`; verified user can.
- Login with wrong password and with unknown email give the same message.
- Login rate limit returns 429 after the threshold.
- Reset with unknown address shows the same page and sends nothing; reset with a known
  address sends mail; the link sets the password, kills all sessions, and verifies an
  unverified user; the link is dead after use.
- Logout deletes the row; the old cookie no longer authenticates.
- Return-to with an absolute URL is ignored.
- `EmailPolicy` unit tests (4.11).
- `User` model: cannot save with neither password nor identity; can save with only an
  identity; cannot remove the last identity from a passwordless user.

### 4.16 Superuser

Runs are private to their owner, plus a superuser who can browse everyone's runs.

- **Who**: addresses listed in `ADMIN_EMAILS`. `User#admin?` is
  `AdminPolicy.admin?(email_address)`, a pure check in the same style as `EmailPolicy`.
  No column, no in-app grant screen, and no request can promote a user. Revocation is a
  config change and takes effect on the next request.
- **What**: `/admin/runs`, every run newest first with the owner's email, filterable by
  user and status, and `/runs/:id` for any run. Read only. A superuser cannot submit
  code as someone else, and there is no delete. `/admin/users` (added after the first
  build) lists every account with its status, run count, and last sign-in, and lets a
  superuser deactivate an account (which ends its sessions), reactivate it, sign it
  out everywhere, send a password reset link, or grant and remove admin access. Each
  action is logged with both ids. A superuser cannot deactivate their own account or
  remove their own admin access.
- **How**: `User#visible_runs` returns `Run.all` for an admin and `runs` otherwise.
  Every run lookup in every controller goes through it, so authorization is one method
  with one call site per action. Views and controllers never ask `admin?` directly;
  they ask a named permission (`can_view_all_runs?`), which today is implemented as
  `admin?`. A third role later is a policy change, not a hunt through templates. The personal `/runs` index stays personal for admins
  too; the admin index is a separate page, and its link in the layout renders only for
  admins.
- **Non-admins** requesting anything under `/admin` get a 404, not a 403, so the area's
  existence is not advertised.
- **Audit**: an admin opening another user's run is logged with both ids.
- **Upgrade path, taken**: admins are now also managed in-app. `admin?` reads a `role`
  column *or* the policy: `ADMIN_EMAILS` still grants access from config, which is how
  the first admin exists and how operations can always get in, and the Users page can
  make a member an admin or remove it. Two guards: nobody can remove their own access,
  and access that comes from config cannot be removed from the page. `admin?` was the
  only call site that changed.

Tests: admin sees every run on `/admin/runs` and can open another user's run; a member
gets 404 on both; the admin link is absent for members; removing an address from
`ADMIN_EMAILS` revokes access on the next request.

---

## 5. Run execution pipeline

### 5.1 Lifecycle

```
POST /runs ──▶ Run(queued) ──▶ ExecuteRunJob ──▶ Run(running) ──▶ container ──▶ one of:
                                                                     succeeded   exit 0
                                                                     failed      non-zero exit (uncaught exception, sys.exit(1), OOM, output cap)
                                                                     timed_out   hit the 120 s deadline
                                                                     errored     the platform failed (Docker unavailable, image missing, worker lost)
```

`failed` means the user's code failed; `errored` means we did. Users should never have
to guess which.

### 5.2 Submitting a run

`RunsController#create` calls `Runs::Submit`, the one place a run is created. The
service validates the code (present, at most `MAX_CODE_BYTES`), enforces the per-user cap
on runs in `queued` or `running`, stamps the run with the current runtime, image, and
limits (section 7), saves it, and enqueues `ExecuteRunJob`. The controller adds a
per-user `rate_limit` (values from config) and redirects to the show page, which says
"Queued" and updates itself when the state changes. A JSON endpoint or a CLI later
calls the same service and inherits every rule.

### 5.3 Job semantics

- **At most once.** User code must never be re-executed automatically. The job has no
  retries. If Solid Queue re-delivers a job after a worker crash, the job sees the run is
  no longer `queued`, marks it `errored` with "worker lost", and stops.
- **Dedicated queue** `sandbox` with its own worker concurrency, so sandbox runs cannot
  starve other jobs and the concurrency number maps directly to host capacity.
- **Per-user fairness** via Solid Queue's `limits_concurrency to: 1, key: user_id`, so
  one person's burst of submissions queues behind their own runs, not everyone else's.
- **Stale run sweeper**: a recurring job marks `running` runs older than
  `timeout + grace` as `errored`, covering the case where the worker died mid-run.
- **Orphan reaper**: a recurring job calls `runner.reap_orphans(older_than:)`. The
  Docker implementation removes containers carrying the app's label; the job itself
  knows nothing about Docker. Belt and braces; the supervisor normally cleans up.

### 5.4 The sandbox

Each run gets a fresh container from a pre-built image (`python:3.12-slim` plus pinned
`numpy`, nothing else, no shell tools beyond what the base image ships). The image and
the command come from a runtime registry, `config/sandbox_runtimes.yml`, with one entry
today (`python3.12`: image, command `python3 -I -u -`). Each run records which entry it
used. Adding a language or a Python version is one entry and one Dockerfile; the form's
runtime select is rendered from the registry and hidden while there is only one entry. The worker
shells out to the Docker CLI with an **argv array**, never a shell string, so the user's
code can never reach a shell.

Code is delivered on **stdin** to `python3 -`. That works identically whether the worker
runs on the host or in a container, needs no shared filesystem, and does not show up in
`ps` or `docker inspect` the way `-c` or an env var would.

```
docker run -i --name run-<id> --label app=pyrun \
  --network none \                        no network at all: no exfil, no SSRF to internal services, no pip
  --read-only \                           immutable filesystem
  --tmpfs /tmp:rw,noexec,nosuid,size=64m \ the only writable path, size-capped, no executables
  --memory 256m --memory-swap 256m \      hard RAM cap, no swap
  --cpus 1 \                              one core
  --pids-limit 64 \                       fork bombs die fast
  --ulimit nofile=256:256 --ulimit core=0 \ no core dumps into tmpfs
  --ipc none \                            no /dev/shm, no SysV IPC
  --cap-drop ALL --security-opt no-new-privileges \
  --user 65534:65534 \                    nobody
  --init \                                proper signal forwarding and zombie reaping
  pyrun-sandbox@sha256:<digest> \         by digest in production, so a tag cannot be swapped
  timeout -s KILL 120 python3 -I -u -
```

Docker's default seccomp profile applies on top. `-I` puts Python in isolated mode
(ignores `PYTHON*` env vars and user site-packages). `-u` unbuffers stdout so partial
output survives a kill. The container inherits **no** environment from the worker, so
there are no app secrets inside it to find.

Optional `--runtime runsc` (gVisor) when the host has it, via `SANDBOX_RUNTIME`. That
adds a user-space kernel between the sandbox and the real one, which is the right next
step for a production deployment; it is not available on Docker Desktop for macOS, which
is why it is a flag rather than a requirement.

### 5.5 Supervision, in the worker

`Sandbox::DockerRunner#run(code, runtime:, limits:)`, where `runtime` and `limits` come
from the run row, not from config, so a run always executes under the values it recorded:

1. `Open3.popen3(*argv)`. Write the code to stdin, close stdin.
2. Two reader threads drain stdout and stderr, keeping the first
   `SANDBOX_MAX_OUTPUT_BYTES` (1 MB) of each. If either stream exceeds the cap, the
   supervisor kills the container and the run is `failed` with "output limit exceeded".
   Draining unboundedly would let `print` in a tight loop push gigabytes through the
   host; stopping reading without killing would block the child on a full pipe until
   the timeout and mislabel it.
3. Wait for the client process with a deadline of `timeout + 5 s`. The in-container
   `timeout -s KILL` is the first line of defence; the supervisor's deadline is the
   second; the reaper is the third.
4. On deadline: `docker kill --signal KILL run-<id>` **by container name**. Killing the
   `docker run` client process does not stop the container, which is the subtle bug in
   most naive implementations.
5. After exit: `docker inspect` for `ExitCode` and `OOMKilled`, then `docker rm -f`. The
   container is not started with `--rm` precisely so that this inspection is possible.
6. Scrub invalid UTF-8 from both streams before storing; Python can print arbitrary bytes.
7. Return a struct: status, exit code, stdout, stderr, truncation flags, duration,
   OOM flag, image digest.

The runner is behind a small interface, `Sandbox::Runner`, with three methods: `run`,
`reap_orphans(older_than:)`, and `healthy?`. `SANDBOX_RUNNER` picks the implementation
(`docker` or `fake`). Tests use the fake, and a gVisor, Firecracker, or remote-runner
implementation is a drop-in later with no change to the job, the reaper, or the tests
that run against the interface.

### 5.6 What each hostile input does

| Input | Outcome |
|---|---|
| `while True: pass` | Killed at 120 s, `timed_out`. |
| `print("x" * 10**9)` | Stream cap trips at 1 MB, container killed, `failed`: output limit exceeded. |
| `[bytearray(10**8) for _ in range(100)]` | cgroup OOM kill, exit 137, `failed` with "memory limit exceeded". |
| `os.fork()` in a loop | `pids-limit` refuses new processes, `BlockingIOError`, `failed`. |
| `open("/etc/passwd").read()` | Reads the container's own file. Harmless; nothing from the host is mounted. |
| `open("/x", "w")` | Read-only filesystem, `OSError`. `/tmp` works but is 64 MB and `noexec`. |
| `socket.create_connection(("169.254.169.254", 80))` | No network namespace interfaces, immediate `OSError`. |
| `subprocess.run(["curl", ...])` | No network, and the image has no curl. |
| `import numpy` | Works, pinned version. |
| `input()` | Immediate `EOFError`, stdin is closed after the code is sent. |
| Emits ANSI escape codes or HTML | Stored as-is, rendered escaped inside `<pre>`. |

### 5.7 Viewing results

`Run` declares `broadcasts_refreshes`. The show page subscribes with
`turbo_stream_from @run`, so when the worker updates the row, Turbo re-renders the page
with a morph. No polling, no JavaScript written by hand. The Action Cable connection
identifies the user from the same signed session cookie, and the stream name is signed,
so a client cannot subscribe to a run it cannot view.

---

## 6. Threat model and controls

| Threat | Control | Where |
|---|---|---|
| Sandbox escape to the host | Unprivileged user, `cap-drop ALL`, `no-new-privileges`, seccomp, read-only rootfs, optional gVisor | 5.4 |
| Exfiltration or lateral movement | `--network none` | 5.4 |
| CPU/memory/process/disk exhaustion | `--cpus`, `--memory`, `--pids-limit`, tmpfs size, output cap, 120 s kill | 5.4, 5.5 |
| One user starving others | Per-user in-flight cap, per-user job concurrency, rate limit | 5.2, 5.3 |
| Command injection via code | argv arrays, code on stdin, never interpolated | 5.4 |
| Secrets leaking into the sandbox | No env passed, no mounts, no network | 5.4 |
| Stored XSS via output | All output rendered through Rails escaping in `<pre>`; strict CSP with nonces | 5.7, 8 |
| Reading another user's run (IDOR) | Every lookup is `Current.user.visible_runs.find(id)` | 4.16, 7 |
| Privilege escalation to superuser | Admin set is deployment config, not a column a request can write; admin views are logged | 4.16 |
| Signing up with an address you do not own | Verification before any feature; link must be opened by the signed-in owner; reset kills sessions; provider linking rules | 4.2, 4.6, 4.8 |
| Credential stuffing, brute force | bcrypt, 12-character minimum, per-IP and per-email limits, uniform errors and timing | 4.7, 4.12 |
| Account enumeration | Uniform responses on signup, login, reset | 4.5, 4.7, 4.8 |
| Token theft or replay | Signed, expiring, bound to a column that changes on use, never stored, never logged | 4.3, 4.12 |
| Login CSRF, OAuth CSRF (later) | Rails forgery protection; POST-only OAuth start with token; `state` check | 4.12, 4.14 |
| Session theft or fixation | Signed HttpOnly Secure cookie, fresh row per login, server-side revocation | 4.9 |
| The worker's Docker access being abused | Web process has no Docker access at all; worker is separate; socket proxy or rootless Docker in production | 10 |
| Vulnerable dependencies | `bundler-audit`, `brakeman` in CI, pinned sandbox base image rebuilt on a schedule | 11 |
| Sensitive data in logs | Code, output, passwords, tokens, and mail bodies are never logged; only ids, emails, statuses | 5, 4.12 |
| Queue flooding | Per-user cap, per-user rate limit, global `MAX_QUEUE_DEPTH`, `RUNS_PAUSED` kill switch | 5.2, 9, 16 |
| Host header poisoning of links in mail | `config.hosts` pinned to the deployed hostname; mail URLs built from `APP_HOST`, never the request | 16 |
| Database file or snapshot leak | `code`, `stdout`, `stderr` encrypted at rest with Active Record Encryption; EBS encryption on | 7, 16 |

What this design does **not** claim: a container is not a virtual machine. A kernel
exploit reachable through the allowed syscalls could escape. For a team-internal tool
behind verified-email login this is an acceptable residual risk; the upgrade path is
gVisor, then microVMs (Firecracker, or Fly Machines), and the runner interface keeps
that swap local.

---

## 7. Data model

```
users
  id, email_address (unique, lowercase), password_digest (nullable),
  email_verified_at (nullable), name (nullable), disabled_at (nullable),
  created_at, updated_at

identities
  id, user_id (fk), provider, uid, email_at_link, last_used_at, created_at, updated_at
  unique (provider, uid), index (user_id)

sessions
  id, user_id (fk, index), ip_address, user_agent, login_method, created_at, updated_at

runs
  id, user_id (fk), status (string enum: queued|running|succeeded|failed|timed_out|errored),
  code (text, <= 64 KB), stdout (text), stderr (text),
  stdout_truncated (bool), stderr_truncated (bool),
  exit_code (int, null), oom_killed (bool), error_message (string, null),
  runtime (string: registry key), sandbox_image (string: image ref + digest),
  timeout_seconds (int), memory_mb (int), cpus (decimal), max_output_bytes (int),
  runner_metadata (json: runner-specific extras such as peak memory or exit signal),
  queued_at, started_at, finished_at, duration_ms (int, null),
  created_at, updated_at
  index (user_id, created_at desc), index (status)
```

Runs are self-describing. Each row records the runtime, image digest, and limits it
actually ran under, stamped by `Runs::Submit` from config at submission time and read
back by the runner at execution time. Changing a default never rewrites history and
never makes an old run ambiguous, and a per-run override later is a form field, not a
runner change. `runner_metadata` takes new metrics without a migration each.

`code`, `stdout`, and `stderr` are declared with `encrypts` (Active Record Encryption,
non-deterministic), so a copied database file or snapshot does not reveal what people
ran. Nothing queries those columns, so losing SQL search on them costs nothing.

Integer primary keys. Access control is scoping, not obscurity; ids being guessable is
fine because every query goes through `Current.user.visible_runs`.

`identities` is created in the first migration even though it stays empty until section
4.14, because the "at least one login method" validation and the settings page are
written against it from the start.

Retention: none for now. A recurring job that clears `stdout`/`stderr` on runs older
than N days is the first thing to add if the table grows.

---

## 8. UI

Plain Rails views, Tailwind via the Rails 8 generator, Turbo for updates. No SPA.

- `/signup`, `/login`, `/passwords/*`, `/verify-email`: one card each, one form each.
- `/runs/new`: a monospace textarea (a small Stimulus controller makes Tab insert
  spaces), a "Run" button, and the limits stated plainly (timeout, memory, CPU, no
  network, output cap), interpolated from config so the copy is never stale.
- `/runs`: the current user's runs, newest first, paginated (Pagy). Columns: when,
  status badge, duration, first line of code. Optional status filter.
- `/runs/:id`: status, timings, exit code, the code, STDOUT in a `<pre>`, STDERR in a
  collapsed `<pre>`, a "Run again" button that prefills the form. Auto-updates while
  queued or running.
- `/admin/runs`: superusers only. Every run with the owner's email, filter by user and
  status, same row layout as `/runs`.
- Layout: app name, signed-in email, "All runs" for admins, "Sign out".

A strict Content Security Policy with per-request nonces for importmap scripts. Output
is never marked `html_safe`.

---

## 9. Configuration

| Variable | Default | Purpose |
|---|---|---|
| `ALLOWED_EMAILS` | my personal address | Comma-separated exact addresses |
| `ALLOWED_EMAIL_DOMAINS` | `windbornesystems.com` | Comma-separated exact domains |
| `ADMIN_EMAILS` | (none) | Comma-separated superuser addresses (4.16) |
| `REQUIRE_EMAIL_VERIFICATION` | `true` | Escape hatch for a broken mail provider. Loud when off. |
| `APP_HOST` | `localhost:3000` | Absolute URLs in mail |
| `MAIL_FROM` | `pyrun@<APP_HOST>` | Sender address |
| `SMTP_ADDRESS`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD` | (none) | Production delivery |
| `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET` | (none) | Section 4.14 only. Button hidden when unset. |
| `SANDBOX_IMAGE` | `pyrun-sandbox:latest` | Image to run |
| `SANDBOX_TIMEOUT_SECONDS` | `120` | Hard kill deadline |
| `SANDBOX_MEMORY_MB` | `256` | cgroup memory cap |
| `SANDBOX_CPUS` | `1` | cgroup CPU cap |
| `SANDBOX_PIDS_LIMIT` | `64` | Max processes in the container |
| `SANDBOX_MAX_OUTPUT_BYTES` | `1000000` | Per-stream cap |
| `SANDBOX_RUNTIME` | (docker default) | e.g. `runsc` |
| `SANDBOX_CONCURRENCY` | `2` | Worker threads on the `sandbox` queue; keep `concurrency × memory` under host RAM |
| `MAX_CODE_BYTES` | `65536` | Submission size cap |
| `MAX_ACTIVE_RUNS_PER_USER` | `5` | Queued + running cap |
| `RUN_RATE_LIMIT` | `20/1m` | Submissions per user |
| `SIGNUP_RATE_LIMIT` | `30/1h` | Global new-account budget (on top of the per-IP limit) |
| `HOST_CPUS` | (none) | Host vCPUs; with `HOST_MEMORY_MB`, required in production so sandbox capacity is validated |
| `SANDBOX_RUNNER` | `docker` | `docker` or `fake` |
| `RETENTION_DAYS` | `0` | Clear stdout/stderr on runs older than this; 0 keeps forever |
| `MAX_QUEUE_DEPTH` | `200` | Refuse new submissions above this many queued runs, with a clear message |
| `RUNS_PAUSED` | `false` | Kill switch: stop accepting submissions while investigating an incident |
| `APP_NAME` | `pyrun` | Layout, titles, mail subjects |

All of these are parsed once, in `config/initializers/pyrun.rb`, into
`Rails.configuration.x.pyrun`, validated at boot (types, ranges, and
`SANDBOX_CONCURRENCY × SANDBOX_MEMORY_MB` under host RAM), and never read from `ENV`
anywhere else. `bin/rails pyrun:config` prints the effective values. Every limit is a
config value so tests can use a 2-second timeout instead of 120.

User-facing copy lives in `config/locales/en.yml`, and any number, domain, or name that
appears in copy is interpolated from config or a policy, never typed into a template.

---

## 10. Deployment and operations

**Local (reviewer or me):** `mise install` (Ruby 3.4), `bin/setup`, `bin/sandbox-build`
(builds the sandbox image), `bin/dev` (Puma, Tailwind watcher, and the Solid Queue worker
from `Procfile.dev`). Docker Desktop must be running. Verification and reset mail shows
up at `/dev/mail`, so the full login flow works with no mail configuration.

**Packaging:** the Rails app ships as one Docker image, built from the `Dockerfile` that
Rails 8 generates (multi-stage, non-root `rails` user, assets precompiled, Thruster in
front of Puma). The same image runs as `web` (`bin/rails server`) and as `job`
(`bin/jobs`); only the command differs, so there is exactly one artifact to build, scan,
deploy, and roll back, and running locally under compose uses the same image as
production. The image adds the static Docker CLI binary so the worker can launch
sandboxes, pointed by `DOCKER_HOST` at the mounted socket locally and at the socket
proxy in production. The sandbox image is a second, separate image from
`sandbox/Dockerfile`; it never contains the app, and the app image never contains
Python. On AWS the app image lives in ECR.

**Local, containerised:** `docker compose up` brings up `web` and `worker` sharing a
volume for the SQLite files. Only `worker` mounts `/var/run/docker.sock`. Sandboxes are
siblings of the worker container, not children, which is why the code goes over stdin
rather than a bind mount.

**Production, on AWS, after everything works locally:** Kamal 2 to a single EC2
instance (Ubuntu, Docker, `t3.small` is plenty), an Elastic IP, a DNS record, and Let's
Encrypt through Kamal's proxy. Two roles on the same instance: `web` (no socket) and
`job` (`bin/jobs`, runs the `sandbox` and `mailers` queues, reaches Docker only through
the socket-proxy accessory below). Health check
on `/up`. The security group allows 80 and 443 from anywhere and 22 from my address
only. Secrets (master key, SMTP, `ADMIN_EMAILS`) go through Kamal's secrets file, sourced
from SSM Parameter Store or a local file that is never committed. Deploy is
`kamal deploy`.

Why EC2 and not ECS or Fargate: the worker needs a Docker socket to launch sandboxes,
and Fargate does not expose one. ECS on EC2 would work but adds a control plane for a
one-host app. When there is a second host, the split is web on anything, workers on
EC2 with the socket.

Mail on AWS: Amazon SES over SMTP. New SES accounts start in sandbox mode, which only
delivers to verified addresses, and production access is a support request that can
take a day, so that request goes in early. A Gmail app password is the fallback if it
is not granted in time, and `REQUIRE_EMAIL_VERIFICATION=false` is the last resort.

Data on AWS: SQLite on the instance's EBS volume with daily snapshots is enough for one
host. RDS Postgres is the swap when there is more than one host or when backups need
to be point-in-time.

The Docker socket is root-equivalent on the host. Mitigations, all but the last in the
plan: keep it away from the internet-facing web process (by design); mount the raw
socket only into a socket-proxy accessory (`tecnativa/docker-socket-proxy`) that exposes
container and image-read endpoints and refuses exec, build, volumes, and networks, with
the exact allowlist discovered by running the integration suite against it; enable
`userns-remap` on the daemon so root inside any container is an unprivileged uid on the
host; and, when the tool outgrows one host, move sandboxes to a separate runner host or
a microVM service (section 12). Honest limit: a proxy restricts which endpoints exist,
not what a `containers/create` body may ask for, so a compromised worker could still
request a privileged container. The worker therefore has no listening port, takes only
a run id as job input, and treats code as opaque bytes it never interprets.

**Sandbox image lifecycle:** built from `sandbox/Dockerfile` by `bin/sandbox-build`, tagged
with the git SHA, digest recorded on every run. Rebuilt on base image updates. Never
pulled at run time; a missing image is an `errored` run within a second, not a hang.

**Observability, minimal:** structured log line per run transition (run id, user id,
status, duration, exit code) and per auth event, never the code, output, passwords, or
tokens. `/up` for liveness. A `bin/rails pyrun:stats` task printing queue depth and
status counts. Real metrics (queue depth, p95 duration, timeout and OOM rates) are the
first thing to add in production.

---

## 11. Testing

Minitest, as generated. Three tiers:

- **Unit**: `EmailPolicy` edge cases; `User` login-method invariants; `Run` state
  transitions and validations; config parsing and boot validation; the supervisor's
  output-capping and UTF-8 scrubbing with a fake process.
- **Runner integration** (tagged, skipped when Docker is absent, runs in CI on Ubuntu
  runners which ship Docker): hello world, the timeout with a 2 s limit, OOM, fork bomb,
  network refusal, read-only filesystem, output cap, non-UTF-8 output, numpy import.
  These are the tests that prove the security claims rather than assert them.
- **Controller and system**: the login cases in 4.15; create run redirects and shows
  queued; after the job runs the output appears; index shows only my runs; another
  user's run id returns 404; rate limit and per-user cap return the right errors.
- **Route coverage**: a test walks every route in the app and asserts that each one
  not on the explicit public list redirects or 404s when signed out. New routes are
  private by default and cannot be forgotten. A second test asserts the security
  headers and that `/rails/*`, `/letter_opener`, and any admin UI are absent in
  production.

CI (GitHub Actions, from the Rails template): rubocop, brakeman, bundler-audit, tests.

---

## 12a. Database: SQLite now, Postgres later (a deliberate choice)

The app ships on SQLite and I would run the internal demo on it. This is a
decision with a known trigger, not an oversight. Interview-ready form:

**Why SQLite is the right call for now.** This is an internal tool for a team,
not a public service. Writes are small, fast, and rarely simultaneous. Rails 8
was built to make SQLite production-grade and applies the right pragmas by
default (verified live): `journal_mode=WAL` so readers and writers don't block
each other, `synchronous=NORMAL`, `foreign_keys=ON`, `mmap_size=128MB`, and a
5-second busy handler set from `timeout: 5000` (installed at the driver level,
so `PRAGMA busy_timeout` reads 0 while the wait is real). The noisiest writer,
Solid Queue's job churn, lives in a **separate** `production_queue.sqlite3`,
with cache and cable split off too, so it never contends with a person
submitting a run. Zero setup for a reviewer, and one less moving part in the
demo.

**What SQLite costs, and why it is not free.**
- **Single host.** The database is a local file, so the app is pinned to one
  server. Workers are otherwise stateless and horizontal; the DB is the one
  thing stopping a second node. This is the real ceiling, not write speed.
- **Backups are volume snapshots, not managed point-in-time recovery.** Restore
  means data loss back to the last snapshot, and a live-file snapshot needs a
  WAL checkpoint first.
- **Writers serialize.** WAL removes reader/writer blocking, but two writers
  still queue; a long write (a big migration, a bulk retention delete) holds the
  lock for its duration.
- **No online replication or failover.** One file, one volume, one point of
  failure.

**The trigger to move to Postgres (RDS).** Any one of: a second app/worker node
is needed for availability or load; managed backups and failover become a
requirement; or the run history becomes data that cannot be lost. The move is a
`database.yml` change plus a data copy, because nothing in the schema or the
queries is SQLite-specific. Until then, Postgres would be operational complexity
bought before it is needed.

## 12. Scaling and evolution

What breaks first, and what I would do:

- **Queue wait time** is the first user-visible symptom. Each run holds a worker slot for
  up to 120 s, so throughput per host is roughly `concurrency / mean duration`. Show
  queue position on the show page; add a second worker host. Workers are stateless
  (code from the DB, output to the DB), so this is horizontal.
- **Database** at that point moves to Postgres (RDS on AWS), which is a config change. Solid Queue
  on Postgres handles far more than this app will see; beyond that, a dedicated queue.
- **Runner isolation** upgrades from runc to gVisor on the runner hosts, then to microVMs
  if the tool ever leaves the trusted-employee population. Fly Machines are an
  attractive shape for the last step: one Firecracker VM per run, destroyed on exit,
  billed per second. The `Sandbox::Runner` interface is the seam.
- **Startup latency** (~0.5 s per container) matters only if people run tiny scripts in
  a tight loop. Fix: a warm pool of paused containers per runner host.
- **Output size** beyond 1 MB moves to object storage with a presigned link, and live
  streaming needs chunked appends over Action Cable rather than one write at the end.
- **Package installation** per run is the most requested feature in tools like this.
  Safe shape: an allowlisted `requirements.txt`, resolved from a private PyPI mirror by
  the worker (not the sandbox), layered into a per-run image, with the sandbox still
  network-free.
- **Login**: Google sign-in (4.14) is the first addition, and it gives automatic
  offboarding. After that, two-factor for password accounts (TOTP is a column and two
  screens), and an admin view of sessions.
- **Retention and cost**: output expiry job, then archival.
- **Team features**: shared visibility is a scope change; sharing links are a token
  column; reproducibility is already covered by the recorded image digest.

---

## 13. Build plan

Milestones in the order I will commit them. Each is a working app.

| # | Milestone | Rough time |
|---|---|---|
| 0 | **Skeleton.** Install Ruby 3.4 via mise, `rails new pyrun --css tailwind` (SQLite, Solid Queue, Solid Cable, Propshaft, importmap). Solid Queue on in development, `bin/jobs` in `Procfile.dev`. The config initializer that reads every env var once, and an empty `en.yml`. `git init`, first commit. | 1 h |
| 1 | **Accounts.** `generate authentication`, then the model from 4.2 (nullable digest, `identities`, `login_method`), `EmailPolicy`, `AdminPolicy` and `can_view_all_runs?`, `Users::Register`, signup, verification, reset changes, logout, `letter_opener_web`, per-action rate limits, the route-coverage test, tests from 4.15. | 3.5 h |
| 2 | **Runs without Docker.** `Run` model with self-describing columns and `encrypts`, runtime registry, `Runs::Submit` and `Runs::Complete`, controller, views, pagination, superuser index, `ExecuteRunJob` against the runner interface, fake runner, `broadcasts_refreshes`. The whole pipeline works end to end with no Docker. | 2.5 h |
| 3 | **Real sandbox.** `sandbox/Dockerfile` and `bin/sandbox-build`, `Sandbox::DockerRunner` with supervision, `reap_orphans`, `healthy?`. Integration tests: hostile inputs from 5.6 and the self-checks from 16.4. | 3 h |
| 4 | **Hardening.** Rack::Attack, queue depth cap and kill switch, sweeper and reaper as recurring jobs, retention job, CSP and headers with their test, `config.hosts`, `__Host-` cookie, `filter_parameters`, `robots.txt`, structured logging, brakeman and bundler-audit clean. | 2 h |
| 5 | **Packaging and docs.** Production `Dockerfile` with the Docker CLI, `docker compose`, README, this document into `docs/`, CI with rubocop, brakeman, bundler-audit, tests, and a Trivy scan. | 1.5 h |
| 6 | **Deploy to AWS**, only once everything above works locally. EC2, security group, SSM, ECR, Kamal with `web` and `job` roles and the socket-proxy accessory, `userns-remap`, SES (production-access request filed early), EBS encryption and snapshots, CloudWatch alarms. | 2 h |
| 7 | **Polish.** Status badges, "Run again", durations, empty states. | 0.5 h |
| 8 | **Stretch: Google sign-in** per 4.14, plus a settings page with linking, sessions list, and "sign out everywhere". | 1 h |

Roughly 17 hours in total. Milestones 0 to 5 are the take-home; 6 is the deployed
demo; 7 and 8 are if time allows.

Repository layout worth noting:

```
app/models/{user,identity,session,run,current}.rb
app/models/{email_policy,admin_policy}.rb
app/services/users/register.rb
app/services/runs/{submit,complete}.rb
app/controllers/concerns/authentication.rb
app/controllers/{registrations,sessions,email_verifications,passwords,runs}_controller.rb
app/controllers/admin/runs_controller.rb
app/controllers/omniauth_sessions_controller.rb          (milestone 8)
app/mailers/user_mailer.rb
app/jobs/{execute_run,sweep_stale_runs,reap_orphan_containers}_job.rb
lib/sandbox/{runner,docker_runner,fake_runner,result}.rb
sandbox/Dockerfile
bin/sandbox-build
config/{deploy.yml,recurring.yml,queue.yml}
config/initializers/pyrun.rb
config/sandbox_runtimes.yml
config/locales/en.yml
docs/DESIGN.md
```

---

## 14. Questions and answers

Moved to [QUESTIONS.md](QUESTIONS.md).

---

## 15. Change map

The test for the design: when someone asks for a change, how many places move? The
rules that keep the answer at one:

1. **Config is read once.** `config/initializers/pyrun.rb` parses and validates every
   env var into `Rails.configuration.x.pyrun`. Nothing else touches `ENV`.
2. **Policies are pure objects with one question each.** `EmailPolicy.allowed?`,
   `AdminPolicy.admin?`. Their source (env now, a table later) is hidden behind them.
3. **Every domain mutation has one service.** `Users::Register`, `Runs::Submit`,
   `Runs::Complete`. Controllers are thin, so a JSON API or a CLI reuses the rules.
4. **Runs are self-describing.** Runtime, image digest, and limits are stamped on the
   row, so defaults can change without touching history or the runner.
5. **The runner interface owns everything Docker-shaped**, including reaping and health.
6. **Copy is in one locale file** and interpolates numbers and names from config.
7. **Authorization is a named question on the user**, never an inline role check.

| If they ask to… | Change | What follows automatically |
|---|---|---|
| Allow another domain or a contractor's address | `ALLOWED_EMAIL_DOMAINS` or `ALLOWED_EMAILS` | Signup, OAuth callback, every-request session check, signup and mail copy, tests |
| Manage the allowlist in-app | `EmailPolicy` reads a table instead of env | All call sites |
| Make runs 5 minutes and 1 GB | `SANDBOX_TIMEOUT_SECONDS`, `SANDBOX_MEMORY_MB` | `docker run` args, supervisor deadline, sweeper threshold, form copy, new runs' recorded limits. Old runs keep theirs. |
| Let users choose a timeout up to a max | `Runs::Submit` accepts it, form gains a field | Runner already reads limits from the run |
| Add Python 3.13 or a second language | One registry entry, one Dockerfile | Form select, run stamping, runner image and command |
| Bump the sandbox image | Registry entry | New runs record the new digest |
| Move sandboxes to gVisor | `SANDBOX_RUNTIME=runsc` | Nothing else |
| Move sandboxes to Firecracker, Fly, or a remote service | One new `Sandbox::Runner` class, `SANDBOX_RUNNER` | Job, reaper, interface tests unchanged |
| Make runs visible team-wide | `User#visible_runs` | Index, show, admin index |
| Add a role | Policy plus one `can_*?` method | Templates and controllers already ask `can_*?` |
| Add Google or Okta sign-in | Section 4.14: gems, one controller, one button | Sessions, gate, allowlist unchanged |
| Add two-factor | One step in `SessionsController#create` before `start_new_session_for`, one column | Shared by every login method |
| Change the mail provider | SMTP env | Nothing else |
| Expire outputs after N days | `RETENTION_DAYS` | The existing recurring job |
| Add a JSON API or CLI | A second controller calling `Runs::Submit` and `visible_runs` | Caps, limits, and authorization reused |
| Move to Postgres | `database.yml` | Nothing else |
| Rename or rebrand | `APP_NAME`, `en.yml` | Layout, titles, mail |
| Change a rate limit or cap | One config value | The controller that reads it |

Where a change is honestly not one place, because it crosses layers:

- **Streaming output while a run is in progress**: the runner yields chunks, the job
  appends them, the row or a side table grows, and the page subscribes to appends. Four
  places, inherent to the feature. The seam that helps is that the runner already reads
  output incrementally in threads.
- **Output to object storage**: the job's write, the `Run#stdout` accessor, and the view
  that renders it. Three places, kept small by never reading the column directly
  outside the model.
- **Leaving Solid Queue**: `limits_concurrency` is Solid Queue's. The per-user in-flight
  cap in `Runs::Submit` is portable and gives most of the value; per-user job
  concurrency would be reimplemented for the new backend.
- **Multi-tenancy**: a policy per organisation and scoping on every query. Not a seam
  this app has, and it should not pretend to.

Scalability follows the same seams. Web is stateless (sessions are rows, so any number
of web nodes work), workers are stateless and horizontal, the runner is swappable, and
the database is the one shared thing, which is why it is the first thing to move to
Postgres. The per-request policy checks are in-memory today, and the note in 4.11
about caching is what keeps them cheap if they ever read from a table.

---

## 16. Security review

Written as a reviewer reading sections 1 to 15 cold. Status tags: **in plan** (already
specified above), **added** (adopted into the plan during this review, and the relevant
section updated), **later** (worth doing, not for the first release).

What is already strong: isolation is OS-level not language-level; the web process
cannot reach Docker; code travels as opaque bytes on stdin; ownership of an address is
proven before anything works; every run lookup goes through one scoped method; the
hostile-input tests prove the sandbox claims rather than assert them.

### 16.1 Reachability and transport

| Control | Status | Note |
|---|---|---|
| HTTPS only, HSTS with a one-year max-age and `includeSubDomains` | in plan | `force_ssl`; Let's Encrypt via Kamal's proxy |
| Security group: 443 and 80 only. No port 22; host access through SSM Session Manager | added | Nothing to brute-force. Kamal deploys over SSH, so 22 stays open to my address only until deploys move to SSM port-forwarding |
| Puma bound to the Docker network, never a public port | in plan | Only the proxy is reachable |
| `robots.txt` disallow all, `X-Robots-Tag: noindex` | added | An internal tool has no reason to be indexed |
| Host authorization: `config.hosts` pinned to the deployed hostname | added | Blocks DNS rebinding and Host-header poisoning of links in mail. Mail links are built from `APP_HOST`, never the request |
| Put the whole app behind a VPN, Tailscale, or an IP allowlist at the security group | later | Strongest control for an internal tool is not being reachable. Depends on whether WindBorne has one |
| Unattended upgrades with a reboot window for kernel patches | added | The kernel is the sandbox boundary; patching it is the top residual-risk control |

### 16.2 HTTP layer

| Control | Status | Note |
|---|---|---|
| Deny-by-default authentication: `require_authentication` in `ApplicationController`, public actions opt out explicitly | in plan | Verified by the route-coverage test in section 11 |
| No public API and no API docs in v1. Any future JSON API uses the same session or hashed per-user tokens; no Swagger UI outside development | added | Nothing to hide because nothing is mounted |
| Dev-only routes (`/rails/info`, `/rails/mailers`, `/dev/mail`) absent in production, asserted by test | added | Rails does this by default; the inbox routes sit behind `Rails.env.local?` |
| Any queue dashboard (Mission Control) behind admin auth or not mounted | added | Solid Queue has no UI by default |
| Action Cable connection authenticates from the session cookie and rejects anonymous connections; stream names are signed | in plan | Test that an unauthenticated socket is refused |
| Rate limiting in two layers: Rack::Attack for per-IP request throttles, auth-path throttles, and a blocklist, backed by Solid Cache; Rails `rate_limit` per sensitive action | added | Section 4 covers the per-action limits; Rack::Attack adds the IP-level brake and a safelist for `/up` |
| Request body cap at the proxy or in middleware, well above 64 KB and well below anything harmful | added | So the code cap cannot be bypassed with a large multipart body |
| Puma slow-client timeouts (`first_data_timeout`, `persistent_timeout`) | added | Cheap Slowloris resistance; the proxy buffers too |
| CSP with per-request nonces, `default-src 'self'`, `frame-ancestors 'none'`, no CDNs | in plan | importmap is vendored, so nothing external loads |
| `X-Content-Type-Options: nosniff`, `Referrer-Policy: strict-origin-when-cross-origin`, minimal `Permissions-Policy`, `Cross-Origin-Opener-Policy: same-origin` | added | Rails sets some; the header test asserts all |
| CSRF protection on every form including the future OAuth start | in plan | |
| Session cookie named with the `__Host-` prefix in production | added | Forces `Secure`, no `Domain`, `Path=/`, so a subdomain cannot plant it |
| `filter_parameters` covers `password`, `password_confirmation`, `token`, and `code` | added | People paste secrets into scripts; the code parameter must not reach logs |
| Production error pages carry no stack traces or version strings; `/up` returns only 200 | in plan | Rails defaults, kept |
| Raw output download, if added, is `text/plain`, `nosniff`, `Content-Disposition: attachment` | later | Never serve user output under an HTML content type |

### 16.3 Accounts and sessions

| Control | Status | Note |
|---|---|---|
| bcrypt, 12-character minimum, uniform errors and timing, per-IP and per-email limits, no lockout | in plan | Section 4 |
| Mandatory verification; link usable only by the signed-in owner; reset kills all sessions; provider linking rules | in plan | Section 4 |
| Breached-password check against the HaveIBeenPwned range API | later | Behind a flag; needs outbound network from web |
| "Sign out everywhere" and a list of active sessions on a settings page | later | Cheap and useful once there is a settings page |
| Idle timeout in addition to the 14-day absolute lifetime | later | An internal tool; revisit if the data sensitivity rises |
| No email-change endpoint exists. If added: re-verify, then terminate sessions | added | Stated so it is a decision, not an omission |
| Admin is deployment config, admin pages are read-only, admin views are logged | in plan | Section 4.16 |
| Sudo mode (re-enter password) before any future admin write action | later | |
| Two-factor (TOTP) for password accounts | later | One step in the login action, one column |

### 16.4 Sandbox and worker

| Control | Status | Note |
|---|---|---|
| No network, read-only rootfs, capped tmpfs, cgroup CPU and memory, pids limit, no capabilities, `no-new-privileges`, unprivileged uid, default seccomp, three-layer timeout, output cap | in plan | Section 5 |
| `--ipc none`, `--ulimit core=0` | added | No `/dev/shm` to fill, no core dumps into tmpfs |
| Run the sandbox image by digest in production | added | A pushed tag cannot change what runs; the digest is already recorded per run |
| `userns-remap` on the Docker daemon | added | Root inside any container maps to an unprivileged host uid |
| AppArmor `docker-default` profile on the Ubuntu host | in plan | Applied automatically; the test asserts it is present |
| Custom seccomp profile tighter than Docker's default | later | Deny `ptrace`, `mount`, `keyctl`, `userfaultfd`, `bpf`, and namespace creation explicitly |
| gVisor on the runner host | later | Section 5.4; a flag once the host has it |
| Docker socket only reachable through the socket proxy; exec, build, volumes, networks refused | added | Section 10 |
| Worker has no listening port, takes only a run id as job input, never interprets code | in plan | Job arguments carry no user content |
| Global queue depth cap and a `RUNS_PAUSED` kill switch | added | Section 9. Per-user limits stop one person; the global cap stops everyone at once during an incident |
| Reject NUL bytes in submitted code and scrub them from output | added | Postgres refuses NUL in text; SQLite does not, so this would surface only after the migration |
| Sandbox self-checks in the integration suite: effective capabilities are zero, only `lo` exists, `/var/run/docker.sock` is absent, rootfs is read-only, the uid is 65534 | added | Proves the flags took effect rather than trusting the command line |
| Host sizing validated at boot: `SANDBOX_CONCURRENCY × SANDBOX_MEMORY_MB` under host RAM | in plan | Section 9 |
| Keep the host kernel patched | added | See 16.1. The boundary is the kernel |

### 16.5 Data and secrets

| Control | Status | Note |
|---|---|---|
| Secrets injected at runtime from Kamal secrets sourced from SSM; never baked into images; `.dockerignore` excludes `master.key` and `.env` | in plan | Section 10 |
| `code`, `stdout`, `stderr` encrypted at rest with Active Record Encryption | added | Section 7. A copied database file or snapshot reveals nothing people ran |
| EBS volume encryption on; SQLite file `0600` | added | |
| Daily snapshots with one tested restore | added | A backup that has never been restored is a hope |
| Retention job clears outputs after `RETENTION_DAYS` | in plan | Section 9. Default keeps forever; production should set it |
| No third-party scripts, analytics, or fonts | in plan | CSP makes this structural |
| Logs carry ids, emails, IPs, and statuses only; shipped to CloudWatch Logs | in plan | |

### 16.6 Supply chain and CI

| Control | Status | Note |
|---|---|---|
| `Gemfile.lock` committed, `bundler-audit` and `brakeman` in CI | in plan | Section 11 |
| Bundler checksum verification (`bundle lock --add-checksums`) and Dependabot | added | |
| Sandbox base image pinned by digest, numpy installed with `--require-hashes`, weekly rebuild with a Trivy scan | added | |
| App image scanned with Trivy in CI; runs as non-root (Rails 8 Dockerfile default) | added | |
| GitHub Actions pinned to commit SHAs with a read-only default token | added | |

### 16.7 Detection and response

| Control | Status | Note |
|---|---|---|
| Structured audit log of auth events, admin views, and run transitions | in plan | Section 10 |
| CloudWatch alarms: failed-login spikes, 5xx rate, queue depth, timeout and OOM rates, Docker daemon errors | added | Timeout and OOM spikes are the abuse signal for a code runner |
| Incident runbook: `RUNS_PAUSED=true`, `pyrun:revoke_sessions`, rotate master key and SMTP credentials, rebuild the host from the image, restore from snapshot | added | Each step is a task or a config change, so it can be done under stress |

### 16.8 What a reviewer should still worry about

- The container boundary is the host kernel. Patching, `userns-remap`, and the seccomp
  and gVisor follow-ups are the mitigations; a microVM runner is the real fix.
- The worker holds Docker access, proxied but real. It is the most valuable target in the
  system, which is why it has no inbound surface and the smallest possible inputs.
- Email delivery is a dependency of login. SES sandbox mode or a provider outage becomes
  a login outage; the escape hatch exists for exactly that and must stay off otherwise.
- Admin membership lives in config. Anyone who can change the deploy environment can
  make themselves admin. That is the same trust as anyone who can deploy at all.
