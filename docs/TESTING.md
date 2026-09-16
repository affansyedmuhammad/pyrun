# Testing

How the project is tested, layer by layer, and how the claims in
[IMPLEMENTATION.md](IMPLEMENTATION.md) are proven rather than asserted.

## The rule

Every change starts with a failing test: write it, watch it fail for the reason you
expect, make it pass, refactor. Commit messages name what was red before the change. A
change without a test that failed before it is not finished. CI runs the whole suite
plus static analysis (RuboCop, Brakeman, dependency audits) on every push.

## Layers

| Layer | What it proves | Where | How to run |
|---|---|---|---|
| Units | Configuration parsing and invariants, policies, outcome classification, output scrubbing, the runner's arguments | `test/lib`, `test/services`, `test/policies`, `test/models` | `bin/rails test test/services` |
| Jobs | At-most-once execution, progress and stop plumbing, the per-person limit | `test/jobs` | `bin/rails test test/jobs` |
| Controllers and views | Escaping, authorization (404 for other people's runs and for non-admins), rate limits, live-stream subscriptions, security headers, the CSP nonce | `test/controllers`, `test/integration` | `bin/rails test test/controllers` |
| Real Docker isolation | Hostile programs against a real daemon | `test/lib/sandbox/docker_runner_integration_test.rb` | part of `bin/rails test` when Docker and the sandbox image are present; skipped otherwise |
| Browser | Sign-up through the verification link, sign-in, the editor, a run updating in place, live output with the clock and bar untouched, Stop, keyboard navigation between runs, admin pages | `test/system` (Playwright, real Chromium) | `bin/rails test:system`; `HEADLESS=false` to watch |
| Configuration as code | `config/puma.rb` registers the right plugins; `config/queue.yml` gives the sandbox worker its threads and poll | `test/config` | `bin/rails test test/config` |

## The hostile programs

The isolation suite runs real programs and checks the outcome and the cleanup:

- a fork bomb, refused by the pid limit;
- a memory bomb, killed by the cgroup and reported as out of memory;
- an infinite loop, killed at the limit and reported as timed out;
- a network probe, finding no interfaces and no DNS;
- filesystem writes, refused everywhere except the small tmpfs;
- a capability and `/proc` probe, finding nothing to escalate with;
- a stdout flood, cut at the cap and killed within a second;
- output that exactly fills the cap, kept whole and not reported as cut;
- arbitrary bytes on stdout, scrubbed rather than crashing anything;
- a program stopped mid-loop on request;
- a check that no container and no secret is left behind.

Each maps to a control in the implementation document.

## Beyond the unit level

The browser tests are the proof for anything visual or live: they drive real Chromium
against a real server thread, receive real Action Cable broadcasts, and assert that
pages update in place (a marker set on `window` must survive, so a full reload fails
the test). Escaping is checked both in controller tests, which look for the escaped
form of a payload in the response, and in the browser, where a script that would set a
global must not run.

## Conventions

- `Sandbox::FakeRunner.respond_with(result, progress: [...])` scripts a runner in any
  test; a lambda can also take `stop_when:` and a progress block.
- `with_config(...)` swaps configuration for a block, so caps and limits are tested at
  their boundaries.
- The isolation suite takes a file lock so parallel test processes never share the
  daemon at the same time.
- Tests pin user-facing copy on purpose; when wording changes, the tests change in the
  same commit.
