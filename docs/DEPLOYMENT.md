# Deployment and operations

How pyrun reaches production and how it is looked after. Hosts, domains, registries
and addresses are supplied through untracked files; nothing environment-specific is
committed.

## Shape

One EC2 instance created by the CloudFormation stack in `deploy/aws/pyrun-stack.yaml`:
a VPC with a public subnet, a security group allowing 80 and 443 from anywhere and SSH
from one address, an instance with Docker preinstalled, and an Elastic IP. Kamal 2
builds one image, pushes it to a registry, and runs it on the host as two roles behind
its TLS proxy: `web` (no Docker socket) and `job` (`bin/jobs`, with the socket). A
`post-deploy` hook builds the sandbox image on the host, because Kamal ships only the
app image. Database files live on a Docker volume. Mail goes out through SMTP.

Why EC2 rather than ECS or Fargate: the worker needs a Docker socket and Fargate has
none; ECS on EC2 adds a control plane for one host. Deleting the stack removes
everything, which suits a disposable account.

## What you supply

1. **A host.**
   ```sh
   aws cloudformation deploy --template-file deploy/aws/pyrun-stack.yaml --stack-name pyrun \
     --capabilities CAPABILITY_NAMED_IAM --parameter-overrides KeyName=<key pair> SSHLocation=<your ip>/32
   aws cloudformation describe-stacks --stack-name pyrun --query "Stacks[0].Outputs" --output table
   ```
   Read the Docker group id once: `ssh -i <key>.pem ec2-user@<host> 'getent group docker | cut -d: -f3'`.
2. **A registry** and a token that can push to it.
3. **A domain** whose A record points at the host; the proxy obtains a certificate.
4. **An SMTP account** (an app password on a mail provider is enough for a demo).
5. **The master key** in `config/master.key`, which decrypts credentials.

## Where the specifics live

`config/deploy.yml` is committed and reads the environment-specific values from
`.kamal/deploy.env`, which is ignored by git:

```sh
PYRUN_SERVER=<host ip>
PYRUN_DOMAIN=<domain>
PYRUN_IMAGE=<registry namespace>/pyrun
PYRUN_REGISTRY_USER=<registry user>
PYRUN_DOCKER_GID=<docker group id on the host>
PYRUN_ALLOWED_EMAILS=<extra addresses, comma separated>
PYRUN_ADMIN_EMAILS=<bootstrap admin address>
PYRUN_SMTP_ADDRESS=<smtp host>
PYRUN_SMTP_USERNAME=<smtp account>
PYRUN_MAIL_FROM=<from address>
```

Secrets are read by `.kamal/secrets` from files that are also ignored:
`config/master.key`, `.kamal/registry_token`, `.kamal/smtp_password`. The SSH key
named in `config/deploy.yml` sits in the project root and is ignored too.

`bin/deploy` loads the env file and runs any Kamal command:

```sh
bin/deploy setup            # first time: proxy, image, both roles
bin/deploy deploy prepare   # once: create the databases on the volume
bin/deploy deploy           # every later release
bin/deploy config           # print the merged configuration
bin/deploy app logs -f -r job
```

## A deploy, step by step

Kamal builds the image for the host's architecture, pushes it, boots the new `web`
container, waits for `/up`, switches the proxy, stops the old `web`, boots the new
`job`, stops the old one, and then the hook rebuilds the sandbox image on the host. The
`web` entrypoint runs `db:prepare`, so migrations apply on boot. Rollback is
`bin/deploy rollback <sha>`.

A deploy restarts the job role, so a run executing at that moment ends as `errored`
(recorded as "worker lost", never re-executed). Deploy between demos, not during one.

## Daily checks

- The health endpoint `/up` answers 200.
- `bin/deploy app exec 'bin/rails pyrun:stats'`: queue depth near zero, `errored` not
  growing.
- On the host, `docker ps` shows one `web`, one `job`, the proxy, and no sandbox older
  than the time limit.
- The instance's CPU credit balance, if it is a burstable type.

`succeeded`, `failed`, `timed_out` and `stopped` describe the program. `errored` means
the platform could not run it. A burst of `errored` is an incident, and the run page
says what the platform hit.

## Incident playbooks

**Runs error instantly with "Cannot connect to the Docker daemon".**
Either a job supervisor is running where it has no socket, or the daemon is down.
`docker top <web container>` must list only Puma; if it lists `solid-queue-*`, the
in-Puma supervisor has been enabled for the web role, which production is designed to
refuse. Otherwise check `systemctl status docker` on the host and
`docker exec <job container> docker version` from inside the job container.

**Runs sit in "Waiting to start".**
The worker is not picking up jobs. Check the job container is running, its logs for a
boot error (a bad setting fails the boot guard on purpose and says which), and
`pyrun:stats` for queue depth. A deploy in progress pauses pickup for about a minute
while the new worker boots.

**A run has been "Running" past the limit.**
The sweeper marks runs `errored` once they exceed the limit plus grace, and the reaper
removes leftover containers. If a container cannot be removed, restarting the Docker
daemon on the host clears it; the containers restart on their own.

**"image not found" on every run.**
The sandbox image is missing on the host (an image prune, or a new host). The
post-deploy hook builds it; by hand:

```sh
scp -i <key>.pem sandbox/Dockerfile sandbox/requirements.txt ec2-user@<host>:~/sandbox/
ssh -i <key>.pem ec2-user@<host> 'cd ~/sandbox && docker build -t pyrun-sandbox:latest .'
```

**A deploy failed halfway.** `bin/deploy rollback <previous sha>`
(`bin/deploy app containers` lists versions). Migrations are additive and never run
backwards.

**No mail arrives.** Check the job logs for the SMTP error. Mail is on its own queue, so
a run backlog never delays it.

**Someone must lose access now.**

```sh
bin/deploy app exec 'EMAIL=<address> bin/rails pyrun:deactivate'   # blocks sign-in, ends sessions
bin/deploy app exec 'bin/rails pyrun:revoke_sessions'               # everyone, everywhere
```

Admins can also deactivate from the Users page.

**The host is slow.** All sandboxes CPU-bound is expected load; the scheduler keeps the
web responsive. Check `uptime`, `free -m`, and `docker ps` for leaked containers.

**Disk is filling.** `docker system df`, `docker image prune -f`. Outputs are capped per
run; set `RETENTION_DAYS` to have old outputs expire daily.

## Secrets

| Secret | Where | Rotation |
|---|---|---|
| Master key | `config/master.key`, injected by Kamal | Rotating it means re-encrypting the encrypted columns with Active Record Encryption's key rotation; plan it, do not improvise it |
| Registry token | `.kamal/registry_token` | Issue a new token, replace the file, redeploy |
| SMTP password | `.kamal/smtp_password` | Issue a new password, replace the file, redeploy |
| SSH key | the `.pem` named in `config/deploy.yml` | New key pair, add the public key to the host user, update the config |

## Backups

A consistent copy of the database while the app runs:

```sh
bin/deploy app exec --reuse 'sqlite3 storage/production.sqlite3 ".backup /rails/storage/backup.sqlite3"'
ssh -i <key>.pem ec2-user@<host> 'docker cp $(docker ps -qf name=pyrun-web):/rails/storage/backup.sqlite3 .'
```

Restore is the reverse plus a restart. This is the cost of SQLite: snapshots, not
point-in-time recovery. The move to Postgres is described in
[FUTURE-SCOPE.md](FUTURE-SCOPE.md).

## Capacity knobs

| Knob | Effect |
|---|---|
| `SANDBOX_CONCURRENCY` | Containers at once; validated against `HOST_MEMORY_MB` and `HOST_CPUS` at boot |
| `MAX_CONCURRENT_RUNS_PER_USER` | Runs at a time per person; never above the total; keep it at half or less |
| `SANDBOX_CPUS`, `SANDBOX_MEMORY_MB`, `SANDBOX_TIMEOUT_SECONDS` | Per-run limits, stamped on each run at submission |
| `MAX_ACTIVE_RUNS_PER_USER`, `RUN_RATE_LIMIT`, `MAX_QUEUE_DEPTH` | Submission caps |
| `RUNS_PAUSED` | Kill switch for submissions during maintenance |

A larger host is one environment change. A second host needs Postgres first.

## Teardown

`aws cloudformation delete-stack --stack-name pyrun` removes the instance, the Elastic
IP, the VPC and everything else. Then revoke the registry token and the SMTP password
and remove the DNS record.
