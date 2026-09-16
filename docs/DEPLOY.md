# Deploying pyrun to production (AWS + Kamal)

The app is packaged and the deploy config is drafted in `config/deploy.yml`. This
runbook lists what you provide, then the ordered steps we run together. The
architecture is one host, two roles from one image: `web` behind Kamal's TLS
proxy (no Docker access) and `job` running `bin/jobs` (the only process with the
Docker socket, which launches sandboxes). See docs/DESIGN.md §10.

## What you provide (the parts I can't create for you)

1. **A host.** An EC2 instance (a `t3.small`, 2 vCPU / 2 GB, is enough to start),
   Ubuntu, with Docker installed and your SSH key authorized. An Elastic IP so
   the address is stable.
2. **A registry.** Where the image is stored. Easiest is GitHub Container
   Registry (ghcr.io) since the code is already on GitHub: create a personal
   access token with `write:packages`. Alternatives: Amazon ECR (AWS-native) or
   Docker Hub.
3. **A domain.** A DNS A record (e.g. `pyrun.yourdomain.com`) pointing at the
   host's Elastic IP. Kamal's proxy gets a free Let's Encrypt certificate for it.
   Without a domain there is no automatic TLS.
4. **A mail sender.** Amazon SES over SMTP is the target, but new SES accounts
   start in sandbox mode (only verified recipients) and production access is a
   support request with a day or so of lead time, so file it early. For an
   immediate demo a Gmail app password works with no lead time.
5. **The master key.** The contents of `config/master.key`, exported as
   `RAILS_MASTER_KEY` when deploying (it decrypts credentials, including the
   encryption keys).

## Fill in config/deploy.yml

Replace every `TODO_...`: the image namespace, server IP, domain, registry
username, `HOST_MEMORY_MB` / `HOST_CPUS` (match the instance), `ADMIN_EMAILS`,
and the SMTP host/username/from. On the host, find the docker group id with
`getent group docker | cut -d: -f3` and uncomment `group-add` in the `job` role
so the worker can read the socket.

## Steps (run together)

```sh
# secrets in your shell, not committed
export RAILS_MASTER_KEY=$(cat config/master.key)
export KAMAL_REGISTRY_PASSWORD=<github token with write:packages>
export SMTP_PASSWORD=<SES SMTP password or Gmail app password>

bundle exec kamal setup      # first time: installs Docker prerequisites, boots the proxy,
                             # builds and pushes the image, starts web + job
bundle exec kamal deploy prepare   # one-off: create the SQLite databases on the volume
```

Then browse to `https://TODO_DOMAIN`, sign up with a company address, click the
verification link from the real inbox, and run a script.

Later deploys are just:

```sh
bundle exec kamal deploy
```

Useful: `kamal logs -f`, `kamal logs -f -r job`, `kamal app exec 'bin/rails pyrun:stats'`,
`kamal rollback`.

## Notes and gotchas

- **DB preparation.** Only the `web` entrypoint runs `db:prepare`. Run the
  `kamal deploy prepare` alias once after the first deploy so the queue/cache/cable
  databases exist before the `job` worker polls them.
- **Build speed.** EC2 is x86_64; building amd64 on an Apple-silicon laptop uses
  emulation and is slow. Options: a Kamal remote builder, or build in GitHub
  Actions and have Kamal pull.
- **Socket access.** If the `job` worker logs "permission denied ... docker.sock",
  the container is not in the host's docker group; set `group-add` (above).
- **SES sandbox.** If real mail does not arrive, check SES is out of sandbox mode
  and the domain/sender is verified, and check the SES sending log. This is the
  usual cause, not the app.
- **Hardening to add after it's live** (see docs/SECURITY-REVIEW.md): front the
  socket with a proxy instead of mounting it raw, enable `userns-remap`, and set
  a non-zero `RETENTION_DAYS`.
