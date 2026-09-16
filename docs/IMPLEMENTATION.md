# Implementation

How pyrun is built and how it behaves. [DESIGN.md](DESIGN.md) is the plan written
before the code; where the two differ, this document describes what exists.

## 1. Overview

**What it does.** A person signs up with a company address, proves they own the inbox,
and submits Python. The program runs in a throwaway container with no network, a
read-only filesystem, a memory and CPU budget and a time limit. What it prints appears
on the run page as it runs, is stored encrypted, and can be browsed later. A run can be
stopped early. Admins see everyone's runs and manage accounts.

**Three processes, three levels of privilege, one Docker image.**

```
                    Internet
                       │ 443 (TLS at the proxy)
               ┌───────▼────────┐
               │     proxy      │  TLS termination, zero-downtime switch between versions
               └───────┬────────┘
                       │
        ┌──────────────▼───────────────┐      ┌──────────────────────────────────┐
        │ web  (Puma)                  │      │ job  (Solid Queue)               │
        │ authenticates, validates,    │      │ sandbox worker: N threads         │
        │ writes Run rows, renders     │      │ default + mailers worker          │
        │ no Docker socket             │      │ mounts the Docker socket          │
        └──────────────┬───────────────┘      └──────────────┬───────────────────┘
                       ▼                                     │ docker run …
        ┌──────────────────────────────┐                     ▼
        │ SQLite (WAL) on a volume:    │      ┌──────────────────────────────────┐
        │ app · queue · cache · cable  │◀─────│ sandbox: one container per run   │
        └──────────────────────────────┘      │ no network, read-only, limits    │
              Solid Cable ──▶ Turbo            │ python3 -I -u -  ← code on stdin │
              (run page, owner's list,         └──────────────────────────────────┘
               admin list)
```

- **web** never talks to Docker. It authenticates, validates, writes a `Run` in status
  `queued`, enqueues `ExecuteRunJob`, and renders pages.
- **job** is the only process that can reach the Docker daemon. It runs the `sandbox`
  queue and, in a separate worker process, the `default` and `mailers` queues, so a
  backlog of runs never delays an email or a page update.
- **sandbox** is a sibling container of `job` on the host daemon, not a nested one. It
  is created per run with every isolation flag from that run's own recorded limits and
  removed when the run ends. The code travels on stdin, never on disk or in an argv.

**Where things live.** One image, tagged by git SHA, runs as both roles; only the
command and the socket mount differ. The sandbox image is separate and never contains
the app. Database files sit on a persistent volume. Every setting is an environment
variable, parsed once at boot by `Pyrun::Config` and validated there.

## 2. A run, end to end

```mermaid
sequenceDiagram
  participant B as Browser
  participant W as web (Puma)
  participant D as SQLite
  participant J as job (Solid Queue)
  participant S as sandbox container
  B->>W: POST /runs with the code
  W->>D: Run (queued) and ExecuteRunJob
  W-->>B: redirect to the run page, subscribed to the run's stream
  J->>D: claim the job (short poll, one at a time per person)
  J->>D: status running
  J->>S: docker run with no network, read-only root, limits; code on stdin
  loop about once a second while running
    S-->>J: stdout and stderr so far
    J->>D: write output so far (no callbacks)
    J-->>B: morph only the output box over the run's stream
    J->>D: stop requested?
  end
  S-->>J: exit code, or killed (time limit, output cap, stop)
  J->>D: Runs::Complete writes the terminal status
  D-->>B: Turbo refresh of the run page, the owner's list, the admin list
```

1. **Submit.** `Runs::Submit` checks, in order: submissions are not paused, the code
   fits the size limit and has no NUL bytes, the person is under their active-run cap
   and their submission rate, and the global queue is under its depth limit. The row
   is stamped with the current limits (timeout, memory, CPUs, pids, output cap), so a
   later configuration change never alters a run in flight.
2. **Queue.** The job carries a per-person concurrency key, so a second run from the
   same person waits until the first finishes. The sandbox worker polls frequently.
3. **Execute.** `Sandbox::DockerRunner` creates the container with no network, a
   read-only root, a small `noexec` tmpfs, memory with no swap, a CPU quota, a pid
   limit, file-descriptor and core-dump limits, no IPC, all capabilities dropped,
   `no-new-privileges`, an unprivileged uid, an init process and a `timeout` wrapper.
   Two reader threads drain stdout and stderr continuously, keeping the first bytes up
   to the cap and discarding the rest, so the container can never block on a full pipe.
   Three timers guard the deadline: `timeout` inside the container, the supervisor's own
   deadline which issues an asynchronous kill, and a last-resort force-remove.
4. **While it runs.** On each one-second wake-up the runner hands the job a snapshot of
   the output so far. `Runs::Progress` writes it without model callbacks and morphs only
   the output section of the run page over the run's stream, so the elapsed clock and
   the progress bar are untouched. The same wake-up honours a stop request: the page
   sets a timestamp on the run, the worker kills the container, and the run ends as
   `stopped`. A queued run asked to stop never starts.
5. **Record.** `Runs::Complete`, the only place a run reaches a terminal status,
   classifies the outcome from the exit code, the OOM flag and the reason for any kill,
   scrubs invalid UTF-8 and NUL bytes, and writes output, truncation flags, duration
   and the image digest in one update. Encryption of `code`, `stdout` and `stderr` is
   transparent in Active Record.
6. **Show.** The commit broadcasts debounced refreshes over Solid Cable to the run's own
   stream, the owner's list stream and the admin list stream. Each open page re-fetches
   itself and Turbo morphs the DOM, so scroll position, filters and focus survive. There
   is no global stream; one person's run never reloads another person's list.

**Statuses.** `queued` and `running` are in flight. `succeeded`, `failed`, `timed_out`
and `stopped` describe what the program did. `errored` means the platform could not
run it and the code is not to blame; the run page shows the platform's message.

**Where the time goes.** For a trivial program on a small instance, creating and
starting the container is the bulk of the cost, roughly a third of a second; Python
itself starts in milliseconds; the wait for a worker is bounded by the poll interval;
classification, scrubbing, encryption and the write are a few tens of milliseconds.
The container start is the floor, and only a warm pool of pre-created containers
would go under it.

## 3. Design decisions and trade-offs

| Decision | Alternatives | Why | Revisit when |
|---|---|---|---|
| **Custom auth** (Rails 8 generator: `has_secure_password`, a `sessions` table, signed tokens) | Devise; OAuth only | Five screens do not need a framework and every line is explainable. An `identities` table exists so Google sign-in attaches to a user later without changing the model. | Two-factor or an SSO-only policy. |
| **Domain allowlist plus inbox verification** | Domain check alone | The domain proves the person can type an address; the link proves they can read the inbox. | An identity provider becomes the verifier. |
| **Sibling Docker containers through the host socket** | Nested Docker; `chroot` and `ulimit`; RestrictedPython; gVisor; Firecracker | OS isolation (namespaces, cgroups, seccomp, dropped capabilities) for free and testable; Python-level sandboxes are not a boundary; sibling rather than nested means no privileged worker. gVisor is a configuration flag away. | The population stops being trusted employees, or a container-escape vulnerability lands. |
| **Code on stdin, limits stamped on the run** | Bind-mounting a file; baking code into an image | Nothing user-controlled touches the host filesystem or the argv; each run records the limits it had; a config change never alters a run in flight. | Multi-file programs or package installs. |
| **SQLite in WAL mode for app, queue, cache and cable** | Postgres from the start | Production-grade in Rails 8, zero setup, the noisy queue in its own file. The real cost is one host. | A second host, managed backups and failover, or run history that cannot be lost. Then Postgres is a `database.yml` change; nothing in the schema or queries is SQLite-specific. |
| **Solid Queue and Solid Cable** | Sidekiq with Redis | No Redis to run, secure or back up; jobs are transactional with the rows they work on. | Sustained tens of jobs a second. |
| **One image, two roles** | Separate images; jobs inside Puma | One artifact to build, scan, deploy and roll back; the only privilege difference is the socket mount. Jobs inside Puma would give the web process Docker access, the one line the design will not cross, and production refuses to boot that way. | Never for jobs inside Puma with the Docker runner. |
| **Kamal on one EC2 host** | ECS or Fargate; a PaaS | The worker needs a Docker socket and Fargate has none; ECS on EC2 adds a control plane for one host. Kamal gives zero-downtime web switches, TLS and rollback with few moving parts. | More than one host. |
| **Encrypt code and output at rest** | Plain text | People paste secrets into scripts; a copied database file reveals nothing without the key. Those columns are not searchable, which nothing needs. | Never. |
| **Two sandboxes at once, one run at a time per person** | One slot; one person may take every slot | Two people never wait for each other, and nobody can monopolize the host. Both numbers are configuration, validated against the host at boot. | A larger host: raise the total and the per-person limit together. |
| **Output capped and the run killed on overflow** | Object storage for large outputs | Bounded memory and one write; a program flooding stdout is stopped in under a second. | Someone needs more than the cap. |
| **Live output as one-second snapshots that morph only the output box** | Per-chunk streaming over Action Cable; a full-page refresh per snapshot | Reuses the encrypted columns, the run's stream and Turbo morph; a late joiner sees everything so far because it is in the database; escaping stays server-side. A full-page refresh would reset the progress widget, so only the output section is morphed. | Per-character latency matters. |
| **Stop through a flag the worker polls** | Signalling the worker process directly | The web tier still never touches Docker; the worker already wakes once a second, so a stop lands within about a second with no new channel. | Sub-second cancellation. |
| **Configuration through one typed reader with a production boot guard** | `ENV` reads at call sites | One place to validate and print; bad values fail the deploy, not a request; string truthiness traps (`"false"`) cannot happen. | Never. |

## 4. Security

**Who gets in.** An allowlisted domain or address, inbox verification bound to the
verification timestamp (so verifying invalidates every outstanding link), bcrypt with a
production cost factor, a minimum length with composition rules, uniform "incorrect
email or password" responses and timing, server-side sessions revocable per person or
for everyone.

**The browser.** A `__Host-` session cookie, HSTS, a Content Security Policy with a
per-session nonce and `object-src 'none'`, no framing, `nosniff`, referrer and
permissions policies, no timing header. Everything user-supplied renders through the
framework's default escaping into a `<pre>`; nothing in the JavaScript builds HTML from
strings; the editor loads code as a text document.

**Abuse limits.** A per-address request limit, a per-person submission rate, a cap on
runs queued or running per person, a global signup budget on top of the per-address
one, and throttled password-reset and verification resends.

**The sandbox.** No network, read-only root, small `noexec` tmpfs, memory with no swap,
a CPU quota, a pid limit, file-descriptor and core-dump limits, no IPC, all capabilities
dropped, `no-new-privileges`, an unprivileged uid, a hard kill at the deadline, and an
output cap. Each control has an integration test that runs a real hostile program
against a real daemon.

**Data.** Code and output are encrypted at rest; the key is injected at deploy and never
committed. Scripts are filtered from request logs and never travel in URLs. The docker
client gets a minimal environment, so no secret reaches a sandbox.

**Boot guard.** Production refuses to start without declared host capacity, with email
verification off, or with the job supervisor inside the web process alongside the
Docker runner.

**Accepted limits** are listed in [FUTURE-SCOPE.md](FUTURE-SCOPE.md): the raw socket
mount, no two-factor authentication, no per-person quota beyond the concurrency cap,
SQLite on one host.

## 5. Performance and capacity

| Layer | Parallelism | Knob |
|---|---|---|
| Web | one Puma process, a few threads | `RAILS_MAX_THREADS`, `WEB_CONCURRENCY` |
| Sandboxes | `SANDBOX_CONCURRENCY` containers, each up to `SANDBOX_CPUS` | validated against `HOST_CPUS` and `HOST_MEMORY_MB` at boot |
| Per person | `MAX_CONCURRENT_RUNS_PER_USER` runs at a time | never above the total; keep it at half or less |
| Mail and broadcasts | a separate worker process | `config/queue.yml` |
| Inside a run | two reader threads and an asynchronous kill | fixed |
| Inside the sandbox | threads or processes up to the pid limit, capped by the CPU quota | `SANDBOX_PIDS_LIMIT` |

Throughput per host is roughly `SANDBOX_CONCURRENCY ÷ mean run duration`. The sandbox
worker polls the queue every 100 ms, so the wait for a free slot is small when one is
free. When every sandbox is CPU-bound the scheduler still shares the cores with the web
process, which stays responsive. The next step up is a larger instance, one environment
change; the step after that is a second job host, which needs Postgres first.

Two things that are not worth optimizing: spawning the `docker` client is tens of
milliseconds per run, and the Ruby-side work per run is similar. The container start
dominates and is the floor.

## 6. Reliability

| Event | What happens |
|---|---|
| The worker dies mid-run | The container's own `timeout` kills it at the limit; the reaper removes it; the sweeper marks the run `errored`. A redelivered job for a run still marked running records "worker lost" instead of running it again, so a program is never executed twice. |
| The Docker daemon is unreachable | Runs go `errored` within a second with the client's message; the web tier is unaffected. |
| A program floods stdout | Cut at the cap and killed; the run is `failed` with a clear explanation. |
| A program exceeds memory | The cgroup kills it; the run says so. |
| A deploy while runs are queued | Jobs are durable rows; they run when the new worker boots. A run executing at the moment the job role restarts ends as `errored`. |
| A container is leaked | The reaper removes labelled containers older than the limit plus grace. |

Recurring jobs: sweep stale runs every minute, reap orphan containers every few minutes,
expire outputs daily when retention is set. Structured one-line log events
(`run.submitted`, `run.finished`, `run.errored`, `admin.run_view`, `admin.run_stop`)
and a `pyrun:stats` task cover the basics; metrics and alerting are future work.
