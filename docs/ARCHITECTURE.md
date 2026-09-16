# pyrun in production: architecture, decisions, performance, and what comes next

This is the "as built and as running" companion to [DESIGN.md](DESIGN.md) (the plan,
written before the code), [SECURITY-REVIEW.md](SECURITY-REVIEW.md) (the attacker's
view and the fixes) and [DEPLOY.md](DEPLOY.md) (the runbook). Where the plan and the
live system differ, this document describes the live system and says why. Every
number in here was measured on the production host during hardening, not estimated.

Live at https://pyrun.duckdns.org. One `t3.small` in `us-east-1`, created by the
CloudFormation stack in `deploy/aws/pyrun-stack.yaml`, deployed with Kamal 2.

---

## 1. The system in one page

**What it does.** A WindBorne employee signs up with a company address, proves they
own the inbox, and submits Python. The program runs in a throwaway container with
no network, a read-only filesystem, 256 MB, one CPU and a two-minute limit. What it
printed is stored encrypted and shown on a page that fills in as the program prints,
with a Stop button to end a run early. Past runs are browsable; admins see everyone's.

**How it is shaped.** Three kinds of process with three levels of privilege, all
from one Docker image:

```
                    Internet
                       │ 443 (Let's Encrypt, HSTS)
               ┌───────▼────────┐
               │  kamal-proxy   │  TLS termination, health-checked switch between versions
               └───────┬────────┘
                       │ 80
        ┌──────────────▼───────────────┐      ┌──────────────────────────────────┐
        │ web  (Thruster → Puma, 3 thr)│      │ job  (bin/jobs = Solid Queue)    │
        │ Rails app, no Docker socket  │      │ sandbox worker: 2 threads         │
        │ writes Run rows, enqueues    │      │ default+mailers worker: 3 threads │
        └──────────────┬───────────────┘      │ dispatcher, scheduler             │
                       │                      │ mounts /var/run/docker.sock (ro)  │
                       ▼                      └──────────────┬───────────────────┘
        ┌──────────────────────────────┐                     │ docker run …
        │ SQLite (WAL) on a volume:    │◀──── polls ─────────┤
        │ app · queue · cache · cable  │                     ▼
        └──────────────────────────────┘      ┌──────────────────────────────────┐
                                              │ sandbox  pyrun-<hex>, per run    │
              Solid Cable ──▶ Turbo refresh   │ --network none --read-only …     │
              (run page, owner's list,        │ python3 -I -u -  ← code on stdin │
               admin list)                    └──────────────────────────────────┘
```

- **web** never talks to Docker. It authenticates, validates, writes a `Run` in
  status `queued`, enqueues `ExecuteRunJob`, and renders pages.
- **job** is the only process that can reach the Docker daemon. It runs the
  `sandbox` queue (containers) and the `default`/`mailers` queue (verification
  mail, Turbo broadcasts) in separate worker processes so a backlog of runs never
  delays an email.
- **sandbox** is a sibling container of `job` on the host daemon (not nested), one
  per run, created with every isolation flag at `docker run` time and removed when
  the run ends. The code travels on stdin, never on disk or in an argv.

**Where it lives.** GHCR holds the app image tagged by git SHA. The host runs
`kamal-proxy`, `pyrun-web-<sha>`, `pyrun-job-<sha>`, and transient `pyrun-<hex>`
sandboxes. The sandbox image is built on the host by a Kamal `post-deploy` hook,
because Kamal ships only the app image. SQLite files live on the `pyrun_storage`
Docker volume. Mail leaves through Gmail SMTP with an app password.

---

## 2. A run, end to end, with real timings

1. **Submit.** `POST /runs` → `Runs::Submit`. Checks, in order: submissions are not
   paused, the code fits 64 KB and has no NUL bytes, the person has fewer than 5
   runs queued or running, they are under 20 submissions a minute, and the global
   queue is under 200 deep. The `Run` row is stamped with the *current* limits
   (timeout, memory, CPUs, pids, output cap), so a later config change never alters
   a run in flight. Redirect to the run page, which subscribes to the run's stream.
2. **Queue.** `ExecuteRunJob` goes on the `sandbox` queue with a per-person
   concurrency key (`MAX_CONCURRENT_RUNS_PER_USER`, 1). Solid Queue holds a second
   run from the same person as *blocked* until the first releases the semaphore.
   The sandbox worker polls every 100 ms.
3. **Execute.** The worker marks the run `running` and calls `Sandbox::DockerRunner`:
   `docker run --name=pyrun-<hex> --network=none --read-only --tmpfs=/tmp:…,size=64m
   --memory=256m --memory-swap=256m --cpus=1 --pids-limit=64 --ulimit=nofile=256:256
   --ulimit=core=0 --ipc=none --cap-drop=ALL --security-opt=no-new-privileges
   --user=65534:65534 --init --pull=never <image> timeout -s KILL 120 python3 -I -u -`.
   Two reader threads drain stdout and stderr continuously, keeping the first
   1,000,000 bytes of each and discarding the rest so the container can never block
   on a full pipe. Three timers guard the deadline: `timeout` inside the container,
   the supervisor's `waiter.join(timeout + 5)` which issues an asynchronous
   `docker kill`, and a last-resort force-remove plus kill of the local client.
4. **Record.** `Runs::Complete` classifies the outcome (exit code, OOM flag, why we
   killed it), scrubs invalid UTF-8 and NUL bytes, and writes stdout, stderr,
   truncation flags, duration and the image digest in one `update!`. Encryption of
   `code`, `stdout` and `stderr` happens in Active Record, transparently.
5. **While it runs.** About once a second the runner hands the job a snapshot of the
   output so far. `Runs::Progress` writes it without model callbacks and morphs only
   the output section of the run page over the run's stream, so the clock and the
   bar keep counting untouched. The same wake-up checks `stop_requested_at`; a Stop
   from the page marks the run, the worker kills the sandbox, and the run ends as
   `stopped`. A queued run asked to stop never starts.
6. **Show.** The commit fires three debounced refresh broadcasts over Solid Cable:
   the run's own stream, the owner's list stream `[user, :runs]`, and the admin
   stream `:all_runs`. Each open page re-fetches itself and Turbo *morphs* the DOM,
   so scroll position, filters and focus survive. There is no global stream; one
   person's run never reloads another person's list.

**Measured on the live host** (trivial `print(0)`, after the capacity tuning):

| Stage | Time |
|---|---|
| Waiting for a worker | 60 to 90 ms |
| Container create + start (Python itself ~10 ms) | 330 to 380 ms |
| Inspect, remove, DB write, broadcast | ~40 ms |
| Submit to finished, total | ~450 ms |
| Status visible in the browser (debounce 500 ms + refresh) | ~1 s |

Raw container cost on this host: `docker run true` 320 to 380 ms, `python3 -c pass`
adds ~10 ms, `import numpy` adds ~300 ms, one `docker` CLI invocation 20 ms.

---

## 3. Decisions and trade-offs

Each row: what was chosen, what it was chosen over, why, and what would make me
change it.

| Decision | Alternatives | Why this one | Revisit when |
|---|---|---|---|
| **Custom auth** (Rails 8 generator: `has_secure_password`, `sessions` table, signed tokens) | Devise, OmniAuth-only | The follow-up asked for our own flow; five screens do not need a framework; every line is explainable. An `identities` table is already there so Google sign-in is one controller and a button. | Two-factor or SSO-only policy arrives. |
| **Domain allowlist + inbox verification** | Domain check alone | The domain proves the person can type; the link proves they read the inbox. Without it anyone could register a coworker's address. | Google sign-in makes the IdP the verifier. |
| **Docker sibling containers via the host socket** | Nested Docker, `chroot`+`ulimit`, RestrictedPython, gVisor, Firecracker | OS isolation (namespaces, cgroups, seccomp, dropped caps) for free and testable; Python-level sandboxes are not a boundary. Sibling not nested: no privileged worker. gVisor is one config flag away (`SANDBOX_RUNTIME=runsc`). | The population stops being trusted employees, or a container escape CVE lands. |
| **Code on stdin, limits at `docker run` time** | Bind-mounting a file, baking code into an image | Nothing user-controlled touches the host filesystem or the argv; each run carries its own limits, so a run in flight is never changed by a config edit. | Multi-file projects or package installs. |
| **SQLite (WAL) for app, queue, cache and cable** | Postgres on RDS from day one | Rails 8 makes SQLite production-grade; zero setup for a reviewer; the noisy queue lives in its own file so it never contends with people. The real cost is *one host*: the file pins the app to a single machine. | A second host is needed for capacity or availability, or run history becomes data that cannot be lost. Then RDS is a `database.yml` change; nothing in the schema or queries is SQLite-specific. |
| **Solid Queue / Solid Cable** (jobs and pub-sub in the DB) | Sidekiq + Redis | No Redis to run, back up or secure; the queue is transactional with the rows it works on. Throughput is far beyond a team tool. | Tens of jobs per second sustained. |
| **One image, two roles** (`web`, `job`) | Separate images, or jobs inside Puma | One artifact to build, scan, deploy and roll back; the only privilege difference is the mounted socket. Jobs inside Puma would give the web process Docker access, which is the line the whole design draws. | Never for jobs-in-Puma with the Docker runner; the boot guard refuses it. |
| **Kamal 2 on one EC2** | ECS/Fargate, Fly, Heroku | The worker needs a Docker socket; Fargate has none. ECS on EC2 adds a control plane for one host. Kamal gives zero-downtime web switches, Let's Encrypt, and `kamal rollback` with almost no moving parts. | More than one host, or a platform team already runs ECS. |
| **Encrypt code and output at rest** | Plain text columns | People paste secrets into scripts. A copied `.sqlite3` file or volume snapshot reveals nothing without `master.key`. Cost: ciphertext is not searchable (not needed). | Never. |
| **Per-person concurrency 1, two sandboxes total** | One slot; one person may take all slots | Two people never wait for each other; nobody can hold every slot. A CPU-bound two-minute run from one person costs the other person nothing. | A 4-vCPU host: raise the total to 4 and the per-person limit to 2. |
| **Output cap 1 MB, kill on overflow** | Object storage for large outputs | Simple, bounded memory. A program flooding stdout is stopped in half a second. | Someone needs more than 1 MB of output. |
| **Live output as one-second snapshots, morphing only the output box** | Per-chunk streaming over Action Cable; full-page refresh per snapshot | Reuses the encrypted columns, the run's stream and Turbo morph; a late joiner sees everything so far because it is in the database; escaping stays server-side. A full-page refresh per snapshot reset the progress widget, so only the output section is morphed. | Per-character latency matters, or a run prints megabytes a second. |
| **Stop through a flag the worker polls** | Signalling the worker process directly | The web tier still never touches Docker; the worker already wakes once a second, so a stop lands within about a second with no new channel. | Sub-second cancellation is needed. |
| **Turbo morph refreshes** | Polling, hand-written Action Cable diffs | Server renders once, the browser re-fetches and morphs. No client state to keep in sync; escaping is Rails' default everywhere. | A page with a JavaScript-built widget (the editor) is *replaced*, not morphed, because morphing broke it once. |
| **Every setting is an env var, parsed once** (`Pyrun::Config`) | Reading `ENV` where needed | One place to validate and print; bad values fail the deploy, not a request; the production boot guard refuses unsafe combinations. | Never. |

---

## 4. Security posture, in short

The full attacker's walkthrough and the twelve findings are in SECURITY-REVIEW.md.
What holds the line today:

- **Who gets in.** Allowlisted domain or address, inbox verification bound to the
  verification timestamp (so verifying kills every outstanding link), bcrypt cost 12,
  12-character minimum with complexity, uniform "incorrect email or password", server
  side sessions revocable per user or globally (`pyrun:revoke_sessions`).
- **The browser.** `__Host-` session cookie, `SameSite`, HSTS two years, CSP with a
  per-session nonce and `object-src 'none'`, `X-Frame-Options DENY`, no `X-Runtime`,
  everything user-supplied rendered through Rails' default escaping. Probed live with
  21 stdout payloads and a hostile first line of code: no dialog, no injected element,
  no CSP violation, on the live update path, the full load, both lists and the editor.
- **Abuse limits.** 300 requests a minute per address (Rack::Attack), 20 submissions
  a minute per person, 5 runs queued or running per person, global signup budget on
  top of a per-address one, password reset and verification resends throttled.
- **The sandbox.** No network, read-only rootfs, 64 MB tmpfs, 256 MB with no swap,
  one CPU, 64 pids, 256 fds, no core dumps, `ipc=none`, all capabilities dropped,
  `no-new-privileges`, unprivileged uid, hard kill at two minutes, output capped.
  Each control has an integration test that runs a real hostile program against a
  real daemon: fork bomb, memory bomb, infinite loop, network probe, filesystem
  writes, stdout flood, arbitrary bytes.
- **Data.** Code and output encrypted at rest; the key never leaves `master.key`,
  injected at deploy. Scripts are filtered from request logs. No secret reaches the
  sandbox: the docker client gets a minimal environment and `unsetenv_others`.
- **Boot guard.** Production refuses to start without declared host capacity, with
  email verification off, or with Solid Queue inside Puma alongside the Docker runner.

Known gaps, accepted for the demo and listed as findings: the raw socket mount
(a socket proxy or `userns-remap` would narrow it), no 2FA, no per-person quota
beyond the concurrency cap, SQLite on one host.

---

## 5. Performance and efficiency: what was measured, what changed, what did not matter

**The floor.** Creating a container on this host costs ~330 ms; Python adds ~10 ms.
That is `containerd` and cgroup setup, not the app. The only way under it is a warm
pool of pre-created containers, which is real complexity for a demo-sized gain.

**What was slow and got fixed.**

- *Queue wait was 675 ms of a 1.07 s run.* The sandbox worker polled every 500 ms and
  ran one container at a time. Now it polls every 100 ms (one indexed query, cheap)
  and runs two containers. A trivial run went from ~1.07 s to ~0.45 s.
- *One person's long run froze everyone.* With one slot, a two-minute regex from one
  user blocked all others. With two slots and one per person, a second user's `print`
  finished in 566 ms while an 8-second run was in progress. Verified that two
  CPU-bound sandboxes at full tilt leave the web answering in 66 to 172 ms.
- *A wasted broadcast per run.* `broadcasts_refreshes` sent every creation to a global
  stream no page subscribed to. Now runs refresh exactly the pages that show them.

**What did not matter.** Spawning the `docker` CLI three times per run costs ~60 ms
total; replacing it with an HTTP client on the socket would buy little and lose the
minimal-environment property. Ruby-side work per run (classification, scrub,
encryption, one `update!`) is ~40 ms.

**What parallelism exists, and where.**

| Layer | Parallelism | Knob |
|---|---|---|
| Web | 1 Puma process × 3 threads | `RAILS_MAX_THREADS`, `WEB_CONCURRENCY` |
| Sandboxes | 2 containers at once, 1 CPU each | `SANDBOX_CONCURRENCY`, `SANDBOX_CPUS` |
| Per person | 1 run at a time | `MAX_CONCURRENT_RUNS_PER_USER` (≤ total, enforced) |
| Mail and broadcasts | separate process, 3 threads | `config/queue.yml` |
| Inside a run | 2 reader threads + async kill | fixed |
| Inside the sandbox | threads/processes up to 64 pids, capped at 1 CPU | `SANDBOX_PIDS_LIMIT` |
| Tests | one worker per core; Docker suite serialized by a file lock | Rails default |

**Capacity math.** The boot guard checks `SANDBOX_CONCURRENCY × SANDBOX_MEMORY_MB ≤
HOST_MEMORY_MB` and `× SANDBOX_CPUS ≤ HOST_CPUS`, and `MAX_CONCURRENT_RUNS_PER_USER ≤
SANDBOX_CONCURRENCY`. On the `t3.small`: 2 × 256 MB of 2 GB, 2 × 1 CPU of 2, with
~900 MB free while two sandboxes idle. Throughput per host is roughly
`concurrency ÷ mean run duration`; the next step is a 4-vCPU host (4 slots, 2 per
person), and after that a second job host, which needs Postgres first.

---

## 6. Reliability and operations

**Deploy.** `kamal deploy` builds the amd64 image, pushes to GHCR, boots the new web
container, waits for `/up`, switches the proxy, stops the old web, boots the new job
container, stops the old one, then the `post-deploy` hook rebuilds the sandbox image
on the host from `sandbox/Dockerfile`. Rollback is `kamal rollback <sha>`. A deploy
takes about a minute when the image layers are cached.

**Failure modes and what happens.**

| Event | Effect |
|---|---|
| Worker dies mid-run | The container's own `timeout` kills it at 120 s; the reaper removes it; the sweeper marks the run `errored`. The job is never re-executed (a redelivered job for a `running` run records "worker lost"). |
| Docker daemon down | Runs go `errored` in under a second with the client's message; the web is untouched. |
| Program floods stdout | Cut at 1 MB, killed, `failed` with "output exceeded"; ~0.5 s. |
| Program exceeds memory | cgroup OOM kill, `failed` with "exceeded its 256 MB memory limit". |
| Deploy while runs are queued | Jobs are durable rows; they run when the new worker boots. |
| Container leaked | `ReapOrphanContainersJob` every 5 minutes removes labelled containers older than timeout + grace. |

**Recurring jobs.** Sweep stale runs every minute, reap orphan containers every
5 minutes, expire outputs daily at 04:00 when `RETENTION_DAYS` > 0.

**Two incidents found while hardening, and what they taught.**

1. *Stdout flood deadlock.* A `while True: print('x'*1000)` wedged the worker and left
   an unkillable container, only on real Linux (Docker Desktop's VM buffers differently).
   The reader stopped draining the pipe to run a synchronous `docker kill`, but the
   process could not die until the pipe drained. Fix: drain continuously, kill
   asynchronously and idempotently. Lesson: test the real host, not just the laptop.
2. *A third of runs erroring with "Cannot connect to the Docker daemon".* `puma.rb`
   enabled the in-process Solid Queue supervisor whenever `SOLID_QUEUE_IN_PUMA` was
   *set*, and deploy.yml set it to `"false"`, which Ruby treats as true. The web
   container, with no socket, was racing the job container for sandbox jobs. Found by
   stracing the worker and seeing it never spawned `docker run` for the failed runs.
   Fix: a real boolean in `Pyrun::Config`, `puma.rb` reads it, production refuses the
   combination, and a test loads `config/puma.rb` and asserts which plugins register.
   Lesson: truthiness of env strings is a classic footgun; put every env read behind
   one typed reader.

**Observability today.** Structured one-line events in the logs (`run.submitted`,
`run.finished`, `run.errored`, `admin.run_view`), `bin/rails pyrun:stats` for queue
depth and counts, `kamal logs`, CloudWatch for CPU and credits. No metrics or alerts
yet; see future scope.

---

## 7. Testing strategy

Everything was written test-first and the history alternates red and green. Four
layers, all green at head (312 unit and integration runs, 1,500 assertions, plus the
Playwright suite, RuboCop, Brakeman and bundler-audit in CI):

- **Pure units.** `Pyrun::Config` parsing and invariants, policies, `Runs::Complete`
  classification and scrubbing, the runner's argv and status mapping.
- **Integration against a real Docker daemon.** Seventeen hostile programs proving each
  isolation claim (fork bomb, memory bomb, timeout, no network, read-only, capability
  drop, output cap, exactly-at-cap, arbitrary bytes, orphan reaping, no leftovers).
  Skipped automatically when Docker is absent; serialized across test processes.
- **Controller and view.** Escaping, authorization (404 for other people's runs and for
  non-admins), rate limits, the live-stream subscriptions each page carries, security
  headers, the CSP nonce.
- **Playwright in real Chromium.** Sign-up through the verification link, login, the
  editor, submitting and watching a run update in place, the list updating in place,
  keyboard navigation between runs, "Run again", the admin pages.
- **Config-as-code tests.** `config/puma.rb` is loaded and checked for which plugins it
  registers; `config/queue.yml` is checked for the sandbox worker's threads and poll.

---

## 8. Future scope, in the order I would do it

1. **Postgres on RDS, then a second job host.** The one structural limit. Also brings
   managed backups and point-in-time recovery.
2. **A socket proxy (or `userns-remap`) in front of `/var/run/docker.sock`** so the
   worker can only `create/start/kill/remove` labelled containers. Narrows the blast
   radius of a worker compromise.
3. **Fair scheduling and quotas.** Per-person daily CPU-seconds, queue position on the
   run page, and a scheduler that alternates people rather than FIFO. Finding 3.
4. **gVisor on the runner hosts** (`SANDBOX_RUNTIME=runsc`), then microVMs (Firecracker
   or Fly Machines) if the tool ever leaves the trusted-employee population.
5. **Google sign-in** (the `identities` table is waiting), then TOTP two-factor for
   password accounts, then a breached-password check at signup.
6. **Package installation** via an allowlisted `requirements.txt` resolved by the
   worker from a private mirror into a per-run image layer, sandbox still offline.
7. **Outputs beyond 1 MB** in object storage behind presigned links, and per-chunk
   streaming if one-second snapshots ever feel slow.
8. **Warm container pool** to cut the ~330 ms start floor, once tiny-script loops are
   a real workload.
9. **Observability.** Request and job metrics, queue-depth and error-rate alerts,
   structured JSON logs shipped off-host, and a deploy annotation.
10. **Operational polish.** SES instead of Gmail, EBS snapshots on a schedule, a CI job
    that deploys on green, and a `job`-role readiness delay so a deploy never races a
    worker boot.

---

## 9. Interview preparation

### Likely questions, with the answer I would give

- **Why Rails, and why so many Rails 8 defaults?** The task is a web app with a queue,
  auth, mail and live updates. Rails 8 ships all of that without Redis or Node, so
  the moving parts are Ruby, SQLite, Docker and an SMTP account. Fewer parts is the
  security story too.
- **How is untrusted code isolated?** A fresh container per run with no network,
  read-only root, tmpfs only, memory and CPU cgroups, a pid limit, no capabilities,
  `no-new-privileges`, an unprivileged uid, and a hard kill at the deadline, plus an
  output cap. The web tier cannot reach Docker at all. The claims are tested with real
  hostile programs against a real daemon.
- **Why not RestrictedPython or a Python-level sandbox?** Every Python-level sandbox
  has been escaped; isolation has to come from the OS.
- **Why Docker and not gVisor or Firecracker?** Not available on the machine a
  reviewer runs this on. The runtime is a config flag and the `Sandbox::Runner`
  interface is the seam for microVMs later.
- **What about the Docker socket in the worker?** It is the design's biggest trust
  assumption: whoever holds it can start containers on the host. Mitigations today:
  only the job process has it, the web never does, everything the worker runs is
  unprivileged and labelled. Next step is a socket proxy limited to the calls we make.
- **Why SQLite in production?** Deliberate and reversible. Team-sized tool, WAL mode,
  separate files for queue, cache and cable, zero setup. The real ceiling is one host,
  not write speed. The trigger to move is a second host or data that cannot be lost.
- **What happens when a run prints 10 MB? Loops forever? Forks? Allocates 4 GB?**
  Cut at 1 MB and killed in half a second; killed at 120 s and marked timed out; pid
  limit refuses the fork; the cgroup OOM-kills it and the run says so. Each is a test.
- **How does the page update live?** State changes commit and the model broadcasts a
  debounced refresh over Solid Cable to the run page, the owner's list and the admin
  list; Turbo re-fetches and morphs the DOM. Output while running is different: once a
  second the worker writes a snapshot without callbacks and morphs only the output box,
  so the progress widget is never touched. No client-side state, no global stream,
  escaping is the server's.
- **How does Stop work without the web talking to Docker?** The page sets a timestamp
  on the run. The worker already wakes once a second for progress; it checks the flag,
  kills the container, and records the run as stopped. A queued run asked to stop is
  marked stopped before any worker picks it up.
- **How would you scale it?** Vertically first (a 4-vCPU host gives four slots and two
  per person, one env change). Then Postgres and more job hosts, since workers are
  stateless. Then a real scheduler with quotas. The per-run floor is the container
  start; a warm pool addresses it if it ever matters.
- **What broke in production and how did you find it?** The stdout flood deadlock and
  the socket-less worker in the web container. Both found by attacking the live host,
  both diagnosed from evidence (a wedged pipe; strace showing no `docker run` spawned),
  both fixed with a test that was red first, and both are now documented gotchas.
- **Why is "Run again" a run id and not the code?** Puma refuses request lines over
  12 KB, and code that is encrypted at rest should not land in browser history or
  proxy logs in clear.
- **Why is the admin an env var and also a role column?** Bootstrap from config,
  manage in-app afterwards; `admin?` is the one call site.
- **How do you prevent a coworker signing up as me?** The domain check gets them a
  form; the inbox verification stops them. If they do register your address first, the
  reset flow proves the inbox is yours, kills their sessions, and verifies you.
- **What would you do differently with more time?** Postgres and a socket proxy before
  going live, metrics and alerts from day one, and a readiness check on the job role
  so deploys never race a worker boot.

### Best practices to point at

- Test-first with the red visible in history; hostile programs as integration tests.
- One typed reader for all configuration; the production boot guard.
- Least privilege per process; the web tier structurally cannot reach Docker.
- Limits stamped on each run, not read at execution time.
- Escaping and CSP as defense in depth, verified in a real browser.
- Small, reversible, measured performance changes with before and after numbers.
- Every incident ends in a regression test and a written gotcha.

### Weak spots to own before they are asked

- SQLite means one host and snapshot-based backups.
- The raw socket mount is broad; the proxy is the next step.
- No metrics or alerting; incidents were found by looking.
- No 2FA; account security rests on the inbox and a strong password.
- Deploys restart the job role, so a run in flight during a deploy would be lost
  (recorded as `errored`, never silently re-run).
