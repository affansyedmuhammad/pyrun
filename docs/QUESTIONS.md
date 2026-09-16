# Questions a reviewer might ask

Short answers, each backed by [IMPLEMENTATION.md](IMPLEMENTATION.md),
[TESTING.md](TESTING.md) or [DEPLOYMENT.md](DEPLOYMENT.md).

- **Why Rails, and why so many Rails 8 defaults?** The task is a web app with a queue,
  authentication, mail and live updates. Rails 8 ships all of that without Redis or a
  Node build, so the moving parts are Ruby, SQLite, Docker and an SMTP account. Fewer
  parts is also the security story.
- **How is untrusted code isolated?** A fresh container per run with no network, a
  read-only root, tmpfs only, memory and CPU cgroups, a pid limit, no capabilities,
  `no-new-privileges`, an unprivileged uid, a hard kill at the deadline and an output
  cap. The web tier cannot reach Docker at all. Every claim is tested with a real
  hostile program against a real daemon.
- **Why not RestrictedPython or a Python-level sandbox?** Every Python-level sandbox
  has been escaped; isolation has to come from the operating system.
- **Why Docker and not gVisor or Firecracker?** Not available on the machine a reviewer
  runs this on. The runtime is a configuration flag, and the runner interface is the
  seam for microVMs later.
- **What about the Docker socket in the worker?** It is the design's biggest trust
  assumption: whoever holds it can start containers on the host. Today only the job
  process has it, the web never does, and everything the worker runs is unprivileged
  and labelled. The next step is a socket proxy limited to the calls the worker makes.
- **Why SQLite in production?** A deliberate, reversible choice for a team-sized tool:
  WAL mode, separate files for queue, cache and cable, zero setup. The real ceiling is
  one host, not write speed. The trigger to move is a second host or data that cannot
  be lost.
- **What happens when a program prints far too much, loops forever, forks, or
  allocates everything?** Cut at the cap and killed within a second; killed at the
  time limit and marked timed out; refused by the pid limit; killed by the cgroup and
  the run says so. Each is a test.
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
- **How would you scale it?** A larger host first: more sandboxes and a higher
  per-person limit, one environment change. Then Postgres and more job hosts, since
  workers are stateless. Then a real scheduler with quotas. The per-run floor is the
  container start; a warm pool addresses it if it ever matters.
- **Why is "Run again" a run id and not the code?** Servers refuse very long request
  lines, and code that is encrypted at rest should not land in browser history or
  proxy logs in clear.
- **Why is the admin an environment variable and also a role column?** Bootstrap from
  configuration, manage in-app afterwards; `admin?` is the one call site.
- **How do you prevent a coworker signing up as me?** The domain check gets them a
  form; the inbox verification stops them. If they register your address first, the
  reset flow proves the inbox is yours, ends their sessions and verifies you.
- **What is the difference between failed and errored?** Failed is the program's
  doing: a non-zero exit, too much memory, too much output. Errored is the platform's:
  the daemon was unreachable, the image was missing, the worker was lost. A burst of
  errored runs is an incident.

## Practices worth pointing at

- Test first, with hostile programs as integration tests and a real browser for
  anything live.
- One typed reader for all configuration and a production boot guard.
- Least privilege per process; the web tier structurally cannot reach Docker.
- Limits stamped on each run, never read at execution time.
- Escaping and a Content Security Policy as defence in depth.
- Every fix ships with the test that was red first and a written playbook when it
  concerns operations.
