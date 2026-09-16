# Deploying pyrun to production (AWS + Kamal)

The app is packaged and the deploy config is drafted in `config/deploy.yml`. This
runbook lists what you provide, then the ordered steps we run together. The
architecture is one host, two roles from one image: `web` behind Kamal's TLS
proxy (no Docker access) and `job` running `bin/jobs` (the only process with the
Docker socket, which launches sandboxes). See docs/DESIGN.md §10.

## What you provide (the parts I can't create for you)

1. **A host.** Created by the CloudFormation stack in `deploy/aws/pyrun-stack.yaml`
   (VPC, public subnet, an EC2 instance with Docker preinstalled, and an Elastic
   IP). See "Provision the host with CloudFormation" below. Deleting the stack
   removes everything, which is why it suits a throwaway account.
2. **A registry.** Where the image is stored. Easiest is GitHub Container
   Registry (ghcr.io) since the code is already on GitHub: create a personal
   access token with `write:packages`. Alternatives: Amazon ECR (AWS-native) or
   Docker Hub.
3. **A domain.** A DNS A record (e.g. `pyrun.yourdomain.com`) pointing at the
   host's Elastic IP. Kamal's proxy gets a free Let's Encrypt certificate for it.
   Without a domain there is no automatic TLS.
4. **A Gmail app password** for sending mail. On the Google account: enable
   2-Step Verification, then Security > App passwords > create one (any name).
   You get a 16-character password; use it as `SMTP_PASSWORD` (enter it without
   spaces). Set `SMTP_USERNAME` and `MAIL_FROM` to that full Gmail address. Gmail
   relays verification and reset mail to any recipient, and a regular account
   sends up to ~500 messages a day, plenty for a demo.
5. **The master key.** The contents of `config/master.key`, exported as
   `RAILS_MASTER_KEY` when deploying (it decrypts credentials, including the
   encryption keys).

## Provision the host with CloudFormation

One stack stands up everything; deleting it tears everything down.

First, in the new account's EC2 console, create a **key pair** (EC2 > Key Pairs >
Create), download the `.pem`, and `chmod 600` it. Then deploy the stack.

Console: CloudFormation > Create stack > upload `deploy/aws/pyrun-stack.yaml`,
set `KeyName` to your key pair and `SSHLocation` to `<your-ip>/32` (from
https://checkip.amazonaws.com), and create it. The **Outputs** tab shows the
public IP.

Or the CLI (with the throwaway account's credentials configured):

```sh
aws cloudformation deploy \
  --template-file deploy/aws/pyrun-stack.yaml \
  --stack-name pyrun \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides KeyName=<your-key-pair> SSHLocation=<your-ip>/32

aws cloudformation describe-stacks --stack-name pyrun \
  --query "Stacks[0].Outputs" --output table
```

Point your domain's A record at the returned IP (or skip the domain and deploy
over the IP with `proxy.ssl: false` for a first pass). SSH in once to confirm
Docker is up and to read the docker group id:

```sh
ssh -i <your-key>.pem ec2-user@<PUBLIC_IP> 'docker --version; getent group docker | cut -d: -f3'
```

Put that group id into the `job` role's `group-add` in `config/deploy.yml`.

### Build the sandbox image on the host (required, once per host)

Kamal ships the **app** image but not the **sandbox** image the worker runs
untrusted code in, so it must exist on the host's Docker daemon or every run
errors with "image not found". After the first deploy, copy the sandbox build
files up and build it there (Docker images persist across reboots and redeploys):

```sh
ssh -i pyrun.pem ec2-user@<PUBLIC_IP> 'mkdir -p ~/sandbox'
scp -i pyrun.pem sandbox/Dockerfile sandbox/requirements.txt ec2-user@<PUBLIC_IP>:~/sandbox/
ssh -i pyrun.pem ec2-user@<PUBLIC_IP> 'cd ~/sandbox && docker build -t pyrun-sandbox:latest .'
```

A follow-up would automate this as a Kamal hook or push the sandbox image to the
registry alongside the app image.

### Teardown (when the demo is done)

```sh
aws cloudformation delete-stack --stack-name pyrun
```

That removes the instance, EIP, VPC, and everything else. Then close the AWS
account from your Organizations console.

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
- **Never set `SOLID_QUEUE_IN_PUMA` for the web role.** The web container has no
  Docker socket. If Puma runs a Solid Queue supervisor, its worker competes with
  the job role for `sandbox` jobs and every run it claims errors instantly with
  "Cannot connect to the Docker daemon" (about a third of runs, since both poll
  the same queue). This happened once because the variable was set to `false`,
  which `if ENV[...]` treats as true; `config/puma.rb` now reads the parsed
  boolean and production refuses to boot with it enabled alongside the docker
  runner. Check with `docker top <web container>`: only `puma` should be listed.
- **Socket access.** If the `job` worker logs "permission denied ... docker.sock",
  the container is not in the host's docker group; set `group-add` (above).
- **Gmail auth.** If mail fails to send, the app password must be from an account
  with 2-Step Verification on, entered without spaces, and `SMTP_USERNAME` /
  `MAIL_FROM` must be that exact Gmail address. Check `kamal logs -r job` for the
  SMTP error.
- **Hardening to add after it's live** (see docs/SECURITY-REVIEW.md): front the
  socket with a proxy instead of mounting it raw, enable `userns-remap`, and set
  a non-zero `RETENTION_DAYS`.
