# Future scope

What would make pyrun better and more robust, in the order it would be worth doing,
with the trigger that makes each item worthwhile, followed by the limits the current
system has by design.

## In order

1. **Postgres on RDS, then a second job host.** The one structural limit today is that
   the database is a file on the host. Moving it also brings managed backups and
   point-in-time recovery. Nothing in the schema or queries is SQLite-specific.
2. **A socket proxy or user-namespace remapping in front of the Docker socket**, so the
   worker can only create, start, kill and remove labelled containers. This narrows what
   a compromised worker could do to the host.
3. **Fair scheduling and quotas.** Per-person daily CPU-seconds, queue position on the
   run page, and a scheduler that alternates between people rather than first-in
   first-out.
4. **Sandbox hardening beyond namespaces and cgroups.** Show a program as little of
   the machine as possible: a runtime with its own kernel view (gVisor is a
   configuration flag away; Firecracker or a per-run VM service after that) so host
   kernel, CPU and memory details are not observable from inside; a smaller sandbox
   image with only the interpreter and its libraries, no shell; a stricter seccomp
   profile than Docker's default; and a routine cadence for host kernel patches.
   Worth doing before the tool serves anyone beyond trusted employees.
5. **Google sign-in**, for which the `identities` table is already in place, then TOTP
   two-factor for password accounts and a breached-password check at signup.
6. **Package installation** through an allowlisted `requirements.txt` resolved by the
   worker from a private mirror into a per-run image layer, with the sandbox still
   offline.
7. **Outputs beyond the cap** in object storage behind presigned links, and per-chunk
   streaming if one-second snapshots ever feel slow.
8. **A warm container pool** to cut the container-start floor, once tiny-script loops
   are a real workload.
9. **Observability.** Request and job metrics, queue-depth and error-rate alerts,
   structured logs shipped off-host, deploy annotations.
10. **Operational polish.** A transactional mail service, scheduled volume snapshots,
    a CI job that deploys on green, and a readiness delay on the job role so a deploy
    never races a worker boot.

## Scaling path

Throughput per host is roughly `SANDBOX_CONCURRENCY ÷ mean run duration`. The first
step is a larger instance: raise the total and the per-person limit together, one
environment change validated by the boot guard. The second is Postgres, which unpins
the database from the host and allows a second job host; workers are stateless, so that
is horizontal. Beyond that, a real scheduler with quotas.

## Known limits, stated plainly

- SQLite means one host and snapshot-based backups rather than point-in-time recovery.
- The job process mounts the raw Docker socket.
- No metrics or alerting; health is checked by looking.
- No two-factor authentication; account security rests on the inbox and a strong
  password.
- A deploy restarts the job role, so a run executing at that moment is lost (recorded,
  never silently re-run).
- Output is capped per run and delivered in one-second snapshots, not streamed per
  character.

## If starting again

Postgres and a socket proxy before going live, metrics and alerts from day one, and a
readiness check on the job role so deploys never race a worker boot.
