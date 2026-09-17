# Changelog

Notable changes by theme, newest first. Commit messages carry the detail for each.

## Live output, control and wording

- A sign-in now ends eight hours after it started, active or not; an hourly job clears
  expired session rows.
- The run page shows what the program has printed so far, about once a second, and
  the output box follows the newest line until the run ends. Only the output section is
  updated while running, so the elapsed clock and progress bar are never disturbed.
- A Stop button ends a run before its limit. Queued runs stop at once; running ones
  end within about a second as the new `stopped` status.
- One plain, calm voice across every screen, flash message and email.

## Performance and fairness

- The sandbox worker polls every 100 ms and the demo host runs two sandboxes at once,
  so a short run finishes in well under a second and one person's long run no longer
  blocks another person.
- Runs at a time per person is a setting, validated to never exceed the total.
- Runs lists update live through per-person streams and an admin stream instead of a
  global one.

## Hardening from attacking the live host

- The web role could run a queue worker without Docker access when the in-Puma
  supervisor flag was set to a non-empty value; configuration is now a typed boolean,
  production refuses that combination, and a test loads the Puma config to check
  which plugins it registers.
- "Run again" refers to the run by id instead of putting the script in the URL.
- Output that exactly fills the cap is reported as complete.
- A stdout flood can no longer wedge the worker or leave an unkillable container:
  readers drain continuously and kills are asynchronous.
- The timing header is no longer sent.

## Deployment

- One image runs as `web` and `job` roles under Kamal 2 on an EC2 host created by a
  CloudFormation stack; a post-deploy hook builds the sandbox image on the host.
  Environment-specific values live in untracked files.
- The production image runs locally with Docker Compose.

## Security review

- An adversarial pass over the running app; fixes for tokens in logs, signup abuse,
  capacity validation, return-path handling and unsafe production configuration. The
  SQLite-now, Postgres-later decision written down with its trigger.

## Product

- CodeMirror editor with Python highlighting; a pager and arrow keys between runs; a
  live clock and progress bar for queued and running runs; password rules with a live
  checklist and a visibility toggle; a development inbox in the app's own design; an
  admin Users page (deactivate, reactivate, reset link, admin grants); sidebar
  navigation and a logo.

## Core

- Rails 8 skeleton with Playwright system tests; a single typed reader for all
  configuration; custom accounts (signup, inbox verification, sign-in, reset, sessions)
  with an identities table ready for Google sign-in and superusers from configuration;
  runs with services, the sandbox interface, the job, the Docker runner and its
  isolation suite; sweeper, reaper, retention, request-size cap, request throttling,
  Content Security Policy and security headers.
