# pyrun — adversarial security review

A hands-on attempt to break the running app, first with no session, then as a
verified user, then from inside the sandbox. Method: live probing of a dev
server plus code review. This lists what held up and what did not, ranked by
severity, each with evidence and a suggested fix. Nothing here was changed in
code; it is a to-do list.

Severity: **High** = exploitable now with real impact. **Medium** = real weakness,
needs a plausible precondition. **Low** = hardening or dev-only. **Info** = accepted
trade-off worth stating.

---

## What held up (attacks that failed)

- **Deny-by-default authorization.** Every protected route (`/`, `/runs`,
  `/runs/:id`, `/admin/runs`, `/admin/users`, `/verify-email`) redirects an
  anonymous request to `/login`. The route-coverage test enforces this for new
  routes too.
- **CSRF.** A tokenless cross-site `POST /login` is refused (422). All state
  changes use non-GET verbs with tokens.
- **IDOR / horizontal access.** Every run lookup goes through
  `Current.user.visible_runs.find`, so another user's run id returns 404;
  members cannot widen their view with `from=all`. Proven by controller tests.
- **Sandbox isolation.** Untrusted Python runs with no network, a read-only
  root, a 64 MB `noexec` tmpfs, cgroup memory/CPU/pids caps, all capabilities
  dropped, `no-new-privileges`, and a three-layer 2-minute kill. Sixteen
  integration tests run real hostile programs (fork bomb, memory bomb, network
  attempt, filesystem write, `/proc` capability probe) and confirm containment,
  cleanup, and that the app's secrets are absent from the container.
- **Transport and headers.** Strict CSP with a per-session nonce, `frame-ancestors
  'none'`, `X-Frame-Options: DENY`, `nosniff`, referrer policy, COOP,
  permissions policy; `force_ssl` + HSTS + host pinning in production.
- **Injection.** Output is rendered escaped inside `<pre>` (no stored XSS);
  every query uses bind parameters and `sanitize_sql_like`.
- **Enumeration.** Signup, login, and reset give uniform responses;
  `authenticate_by` gives uniform timing.
- **Secrets.** The web process cannot reach Docker; sandboxed code cannot reach
  the Docker socket, the app environment, or any mounted secret.

---

## Findings

### 1. Reset and verification tokens are written to the request log — Medium
**What.** The password-reset link is `/passwords/<token>/edit` and the
verification link is `/verify-email/<token>`. The token is a *path segment*, and
`config.filter_parameters` only filters request *parameters*, so the full token
lands in the log.
**Evidence (live).** After hitting a reset link, the dev log contained:
`Started GET "/passwords/eyJfcmFpbHMiOnsiZGF0YSI6WzEs...` — the entire 182-char
token in clear text.
**Impact.** Anyone who can read production logs (CloudWatch, a log shipper, a
leaked file, a support engineer) can lift an unexpired token and complete a
password reset (15-min window) or verify an account (24-h window), taking it
over. Logs are usually lower-trust than the database.
**Fix.** Deliver the token in a way that does not appear in the path: accept it
as a POST body / form field, or a short opaque id plus a filtered param, or
scrub `/(passwords|verify-email)/[^/]+` from the logged path with a small
`config.log_tags` / request-log filter. At minimum, shorten token lifetimes and
document that logs are secret-bearing.

### 2. Signup creates an account and sends mail for any address on the domain, before inbox control is proven — Medium
**What.** `POST /signup` with any syntactically valid `@windbornesystems.com`
address passes `EmailPolicy`, creates a `User` row, and enqueues a verification
email. Rate limit is 10 per 15 min per IP.
**Evidence (live).** A scripted signup for `pentest.<ts>@windbornesystems.com`
returned 303 to check-inbox and created the row and mail with no inbox proof.
**Impact.** (a) Resource/DB pollution and outbound-email volume to
possibly-nonexistent company mailboxes → SES bounce rate and sender reputation
damage, which can get the whole domain's mail throttled. (b) An attacker can
send unsolicited "verify your pyrun account" mail to real coworkers who never
signed up. From several IPs this scales.
**Fix.** Throttle new-account creation globally (not only per IP), add a simple
proof-of-work or CAPTCHA on signup, cap unverified accounts per time window,
and monitor bounce rate. Consider not creating the row until the first
verification click for brand-new addresses.

### 3. A few verified accounts can monopolize all sandbox capacity — Medium (availability)
**What.** `ExecuteRunJob` limits one *running* job per user
(`limits_concurrency to: 1, key: user_id`), and the sandbox queue runs
`SANDBOX_CONCURRENCY` threads (default 2). There is no global per-time budget or
fair scheduler.
**Impact.** Two verified (or compromised) accounts, each submitting the max 5
active runs of up to 2 minutes, keep both worker threads busy indefinitely.
Everyone else's runs queue behind them — a denial of service of the core
feature, using only in-policy behavior.
**Fix.** A per-user daily/hourly run quota; more workers or autoscaling; a fair
scheduler that round-robins across users; surface queue position so the effect
is visible. The global `MAX_QUEUE_DEPTH` caps memory but not starvation.

### 4. Production runs on a single SQLite database for app, jobs, cache, and cable — Medium (availability / scalability)
**What.** `config/database.yml` production uses SQLite files for `primary`,
`queue`, `cache`, and `cable`. SQLite is single-writer with a 5 s busy timeout.
**Impact.** Under concurrent load the web writes, Solid Queue polling/updates,
Rack::Attack counters, and cable all contend on one writer. Bursts can raise
`SQLite3::BusyException` → 500s, and the single file is a single point of
failure with no online replication. The design doc names the Postgres path but
it is not the shipped default.
**Fix.** Move to Postgres (RDS) before real multi-user load, as the design doc
plans; at minimum split the queue/cache/cable onto separate SQLite files (partly
done) and enable WAL with a longer busy timeout, and back up/restore-test the
volume.

### 5. The memory safety check is off by default, and CPU is never validated — Low–Medium (availability)
**What.** Boot validation raises only when
`SANDBOX_CONCURRENCY × SANDBOX_MEMORY_MB > HOST_MEMORY_MB`, and `HOST_MEMORY_MB`
defaults to `nil`, so the check is skipped unless explicitly set. CPU
(`SANDBOX_CONCURRENCY × SANDBOX_CPUS` vs host vCPUs) is never checked.
**Impact.** On a small host (for example a 2-vCPU t3.small) two runs at
`--cpus=1` can consume 100% CPU and starve Puma and the worker, and the memory
guard that would have caught an over-provisioned config is inert by default.
**Fix.** Detect host memory/CPU at boot (or require `HOST_MEMORY_MB` and a new
`HOST_CPUS` in production) and validate both; give sandboxes a CPU weight below
the app's.

### 6. Run history is unbounded by default — Low (availability / cost)
**What.** `RETENTION_DAYS` defaults to `0` (keep forever). Each run stores
encrypted code plus up to 1 MB each of stdout/stderr.
**Impact.** Storage grows without limit; on SQLite/EBS this eventually fills the
volume, which takes the app down.
**Fix.** Ship a non-zero retention default in production, alert on disk usage,
and archive old output to object storage.

### 7. No lockout; distributed credential stuffing is feasible — Low–Medium
**What.** Login limits are 10 per 3 min per IP and a deliberately loose 30 per
15 min per email. There is no account lockout, 2FA, or breached-password check.
**Impact.** An attacker with a leaked company password list and many IPs can try
~120 passwords/hour against a chosen account. For password accounts with no
second factor this is the most realistic account-takeover path.
**Fix.** Add TOTP 2FA (already a planned item), a HaveIBeenPwned range check on
password set, and consider a progressive per-account delay.

### 8. Development-only surfaces are unauthenticated — Low (dev-only)
**What.** `/dev/mail` (the inbox, with every verification and reset link) and
`/rails/info/*` return 200 with no session in development.
**Evidence (live).** The anonymous `/dev/mail` listing exposed message links; the
message page exposed the verification URL. These routes are guarded by
`Rails.env.local?` / not mounted in production.
**Impact.** Only if a developer binds the dev server to a non-loopback address
or exposes it through a tunnel: anyone reaching it can read every reset and
verification link and take over accounts. The probe server here was bound to
127.0.0.1 only.
**Fix.** Keep the dev server on loopback; optionally gate `/dev/mail` behind a
basic check even in development. No production exposure today.

### 9. The open-redirect guard is weak against backslashes — Low (latent)
**What.** `safe_return_path` accepts a target that starts with `/` and not `//`.
`"/\\evil.com"` passes the guard, and browsers normalize the backslash so the
redirect would leave the origin.
**Impact.** Not currently exploitable: the return-to value is `request.fullpath`
of a *routable* protected path, and `/\evil.com` does not route (it 404s before
the value is stored). This is a latent weakness if the source of the value ever
changes.
**Fix.** Validate with a stricter rule (reject any `\`, or parse with `URI` and
require a relative path with no host), rather than a `start_with?` check.

### 10. `REQUIRE_EMAIL_VERIFICATION=false` is a foot-gun — Low
**What.** The escape hatch, if ever set in production, lets anyone who can type a
`@windbornesystems.com` address use the app without proving inbox control.
**Impact.** Defeats finding-2's only compensating control (the verification
gate). It is off by default and shows a loud banner.
**Fix.** Refuse to boot with it false in production, or require a second
explicit override variable.

### 11. Reset emails can be aimed at real users — Info
Password-reset requests for a real address send that user mail (rate-limited 5
per 15 min per email, 10 per 15 min per IP). Enough to annoy, not to take over.
Accepted trade-off of the uniform-response design.

---

## Suggested order of work

1. Finding 1 (token in logs) — cheap, clear account-takeover path from logs.
2. Finding 4 (Postgres) and 3 (run quota) — the availability story before real load.
3. Finding 2 (signup abuse) and 7 (2FA / breached-password) — account-abuse surface.
4. Findings 5, 6, 9, 10 — hardening and safe defaults.
