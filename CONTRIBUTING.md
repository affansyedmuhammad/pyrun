# Contributing to pyrun

How to set up, how the work is done, where things live, and how to add the common
things. Read [docs/IMPLEMENTATION.md](docs/IMPLEMENTATION.md) first if you have not.

## Setup

Requirements: Docker (Desktop is fine), Ruby 3.4 (`brew install mise && mise install`
reads `.ruby-version`), Node 18+ (only for the Playwright browser used by system tests).

```sh
bin/setup          # gems, databases, Playwright's Chromium, the sandbox image
bin/dev            # web on http://localhost:3000, Tailwind watcher, job worker
```

Sign up with a `windbornesystems.com` address or put yours in `.env` (see
`.env.example`). Verification and reset mail lands at http://localhost:3000/dev/mail.
Without Docker, `SANDBOX_RUNNER=fake bin/dev` runs everything with a runner that
executes nothing.

## How the work is done

**Test first, always.** Write the failing test, watch it fail for the reason you
expect, make it pass, refactor. Commit the test with (or before) the implementation and
say in the message what was red. A change without a test that failed before it is not
finished.

**Before committing:** `bin/rails test`, the relevant `bin/rails test test/system/...`
files (they drive real Chromium), `bin/rubocop`, and `bin/brakeman` if you touched
controllers, models or views. CI runs all of these plus `bin/bundler-audit` and
`bin/importmap audit`.

**Commit messages** are prose, not tags: a one-line summary in the form
`Area: what changed`, then a paragraph on why, what the symptom was, what the test
proved, and any decision or finding it relates to. Read `git log` for examples; the
history is meant to be readable as a story.

**Nothing user-facing changes without its copy.** Wording lives in views and
`config/locales/en.yml`, and follows the voice below.

## Code map

```
app/controllers        thin; one action per verb, all lookups through Current.user.visible_runs
app/services           the only places users and runs are created, progressed, stopped or completed
  users/register.rb    signup
  runs/submit.rb       validation, caps, enqueue
  runs/progress.rb     output so far while running (no callbacks, targeted morph)
  runs/stop.rb         end a run early
  runs/complete.rb     the only place a run reaches a terminal status
app/models             User, Identity, Session, Run (statuses, streams, encryption)
app/policies           pure questions: who may sign up, who is an admin
app/jobs               ExecuteRunJob and the recurring sweep, reap and expire jobs
app/helpers            status labels, explanations, formatting
app/javascript         Stimulus controllers: editor, elapsed clock, follow-output, pager keys
lib/pyrun/config.rb    every environment variable, parsed and validated once
lib/sandbox            the runner interface, the Docker runner, the fake, runtimes, limits
sandbox/               the image untrusted code runs in
config/deploy.yml      Kamal roles, env, volumes (host specifics from .kamal/deploy.env); .kamal/hooks builds the sandbox image
deploy/aws             the CloudFormation stack for a throwaway host
test/                  mirrors app/ and lib/; test/system is Playwright; test/config pins config files
docs/                  see docs/README.md
```

Rules that keep changes small (from DESIGN §15): configuration is read once in
`Pyrun::Config`; policies answer one question each; every mutation has one service;
runs are self-describing (limits stamped on the row); the runner interface owns
everything Docker-shaped; authorization is a named question on the user.

## Testing guide

| Layer | Where | Run |
|---|---|---|
| Units (config, policies, services, runner argv and classification) | `test/lib`, `test/services`, `test/policies`, `test/models` | `bin/rails test test/services` |
| Jobs | `test/jobs` | `bin/rails test test/jobs` |
| Controllers and views (escaping, authorization, streams, headers) | `test/controllers`, `test/integration` | `bin/rails test test/controllers` |
| Real Docker isolation suite | `test/lib/sandbox/docker_runner_integration_test.rb` | runs inside `bin/rails test` when Docker and the image are present, otherwise skips |
| Browser (Playwright, real Chromium) | `test/system` | `bin/rails test test/system/runs_test.rb`, or `bin/rails test:system` for all |
| Config files as code | `test/config` | `bin/rails test test/config` |

Useful switches: `-n "/pattern/"` runs matching tests; `HEADLESS=false` shows the
browser during system tests; `Sandbox::FakeRunner.respond_with(result, progress:)`
scripts a runner in any test; `with_config(...)` swaps configuration for a block.

## How to add common things

- **A configuration setting.** One line in `Pyrun::Config::SETTINGS` with its parser
  and default, a test in `test/lib/pyrun/config_test.rb`, and if it must hold in
  production, an entry in `production_safety_errors`. Never read `ENV` elsewhere.
- **A run status.** Add it to `Run::STATUSES` (and `TERMINAL_STATUSES` if it ends a
  run), a label, dot and explanation in `RunsHelper`, the transition in a service,
  and `DockerRunner.status_for` if the runner can produce it. Filters pick it up.
- **A page that updates live.** Subscribe with `turbo_stream_from` to the narrowest
  stream that makes sense (a person, a run, `:all_runs`), add the two `turbo-refresh`
  meta tags if the page has no JavaScript-built widgets, and broadcast from the
  model's commit callbacks. Never a global stream.
- **A sandbox runtime.** An entry in `config/sandbox_runtimes.yml` (image, command that
  reads code from stdin); the runner and the form pick it up.
- **An admin action.** A member route under `admin/users`, one service call, a
  `button_to` with an accessible name, a controller test for members getting a 404.
- **Copy.** Change the view or `config/locales/en.yml`, then the tests that pin it.

## Copy voice

Clear and direct, neither formal nor casual, the way product copy reads in Google or
Apple apps. Sentence case. Contractions are fine. Say what happened and what to do
next, in that order. No exclamation marks, no jokes, no jargon in user-facing text
("Waiting to start", not "Waiting for a worker"). Status explanations are one sentence.

## Troubleshooting

- **Runs error at once with "Cannot connect to the Docker daemon".** Docker Desktop is
  not running, or the process running jobs cannot see the socket. In development,
  `docker info` must work in the shell that runs `bin/dev`.
- **"image not found" or the isolation suite skips.** Build the sandbox image:
  `bin/sandbox-build`.
- **System tests cannot find Chromium.** `npx playwright install chromium`.
- **Port 3000 is taken.** `PORT=3001 bin/dev`.
- **The editor looks like a plain textarea after navigating.** The CSP nonce changed
  mid-session; see the comment in `config/initializers/content_security_policy.rb`.
- **No verification mail.** In development it is at `/dev/mail`; in production check
  the job logs for the SMTP error and docs/DEPLOYMENT.md.
