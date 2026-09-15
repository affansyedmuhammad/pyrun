# pyrun

Submit Python, run it in an isolated sandbox for up to two minutes, keep what it printed, browse past runs. Built for the WindBorne take-home. The design, threat model, and change map are in [docs/DESIGN.md](docs/DESIGN.md).

## Run it locally

Requirements: Docker (Desktop is fine), Node 18+ (only for the Playwright browser used by system tests), and Ruby 3.4. `mise` installs Ruby from `.ruby-version`:

```sh
brew install mise && mise install      # Ruby 3.4
bin/setup                              # gems, databases, Playwright's Chromium, the sandbox image
bin/dev                                # web on http://localhost:3000, Tailwind watcher, and the job worker
```

Sign up with a `windbornesystems.com` address (or add your own to `ALLOWED_EMAILS`). Verification and reset mail opens in the browser at http://localhost:3000/letter_opener. Nothing else needs configuring.

Without Docker, `SANDBOX_RUNNER=fake bin/dev` runs the whole app with a runner that executes nothing.

## Tests

```sh
bin/rails test              # unit and integration, plus the Docker isolation suite when the image is built
bin/rails test:system       # Playwright, real Chromium
bin/rubocop && bin/brakeman && bin/bundler-audit
```

Every feature was written test-first; the history alternates red and green commits.

## Configuration

Everything is an environment variable, read once at boot and printed by `bin/rails pyrun:config`. The full table is in docs/DESIGN.md §9. The ones you are most likely to set:

| Variable | Default | Purpose |
|---|---|---|
| `ALLOWED_EMAIL_DOMAINS` | `windbornesystems.com` | Who may sign up (exact domain match) |
| `ALLOWED_EMAILS` | none | Extra individual addresses |
| `ADMIN_EMAILS` | none | Superusers who can browse everyone's runs |
| `SANDBOX_TIMEOUT_SECONDS` / `SANDBOX_MEMORY_MB` / `SANDBOX_CPUS` | `120` / `256` / `1` | Per-run limits, stamped on each run |
| `SANDBOX_CONCURRENCY` | `2` | Runs in flight at once; validated against `HOST_MEMORY_MB` |
| `SANDBOX_RUNNER` | `docker` | `fake` runs nothing, for development without Docker |
| `RETENTION_DAYS` | `0` | Delete run output after this many days (0 keeps it) |
| `RUNS_PAUSED` | `false` | Kill switch for submissions |

## Operations

```sh
bin/rails pyrun:stats                                  # queue depth and counts
EMAIL=person@windbornesystems.com bin/rails pyrun:deactivate
bin/rails pyrun:revoke_sessions                        # sign everyone out
bin/sandbox-build                                      # rebuild the sandbox image (tagged with the git SHA)
```

## Layout

- `app/policies` — who may sign up, who is an admin (pure, config-backed)
- `app/services/users`, `app/services/runs` — the only places users and runs are created or completed
- `lib/sandbox` — the runner interface, the Docker runner, the fake, the runtime registry
- `sandbox/` — the image untrusted code runs in
- `docs/DESIGN.md` — why everything is the way it is
