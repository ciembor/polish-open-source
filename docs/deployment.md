# Deployment

The app is deployed behind nginx at `https://polish-open-source.pl`. The
application and jobs run as Podman containers managed by systemd:

- [deploy/polish-open-source-rank.service](../deploy/polish-open-source-rank.service)
- [deploy/polish-open-source-rank-monthly.service](../deploy/polish-open-source-rank-monthly.service)
- [deploy/polish-open-source-rank-monthly.timer](../deploy/polish-open-source-rank-monthly.timer)
- [deploy/polish-open-source-rank-packages.service](../deploy/polish-open-source-rank-packages.service)
- [deploy/polish-open-source-rank-packages.timer](../deploy/polish-open-source-rank-packages.timer)
- [deploy/polish-open-source-rank-crawl.service](../deploy/polish-open-source-rank-crawl.service)
- [deploy/polish-open-source-rank-crawl-resume.service](../deploy/polish-open-source-rank-crawl-resume.service)

## GitHub Actions Flow

GitHub Actions runs named quality and security jobs before deploy. The deploy
job depends on those inspectable gates and then calls
[scripts/deploy.sh](../scripts/deploy.sh).

Required repository secrets:

- `SSH_PRIVATE_KEY_B64`: base64-encoded private SSH key accepted for
  `ciembor@maciej-ciemborowicz.eu`.
- `SSH_KNOWN_HOSTS`: pinned SSH host key lines for
  `maciej-ciemborowicz.eu`, in OpenSSH `known_hosts` format. Populate this
  secret from a trusted administrative source, not from deploy-time
  `ssh-keyscan` output.

The workflow pins GitHub Actions by commit SHA. The trailing version comments
show the reviewed upstream version and are the expected target for dependency
update PRs.

The `CI and deploy` workflow supports two actions:

- normal `deploy` on every push to `master`;
- manual `rollback` through `workflow_dispatch`, limited to swapping back to the
  immediately previous image.

The workflow also builds the production container and starts it with
production-like environment variables before deploy. That smoke test verifies
`/healthz`, non-root execution, and writable `db`, `log`, and `tmp` runtime
directories.

The deploy script does not touch running monthly or package jobs. It restarts
only the web and Discord bot services, then waits for built-in smoke checks on
local `/healthz` plus public `/healthz`, `/latest`, and `/en/latest` before the
release is treated as healthy.

Production deploys currently run directly from the protected `master` branch
without a GitHub Environment approval gate. That matches the single-operator
production model; add a `production` GitHub Environment with required reviewers
before granting additional maintainers deploy permission.

## Production Topology

- The production host is `ciembor@maciej-ciemborowicz.eu`.
- The app checkout lives in `/home/ciembor/polish-open-source-rank`.
- The web app runs in the `polish-open-source-rank` Podman container.
- nginx terminates TLS and forwards `/internal/*` to the Rack app. The app owns
  Basic Auth for those routes through `INTERNAL_BASIC_AUTH_USERNAME` and
  `INTERNAL_BASIC_AUTH_PASSWORD` in `.env.local`; use
  [deploy/nginx-polish-open-source-rank-internal.conf](../deploy/nginx-polish-open-source-rank-internal.conf)
  as the expected server block snippet.
- The Rack app emits security headers, including HSTS, for public, auth, badge,
  and internal responses. Edge and nginx config may also emit HSTS, but the app
  middleware is the repository-owned regression surface.
- The production web unit sets `GOOGLE_ANALYTICS_MEASUREMENT_ID=G-QHRZZZLKPE`.
  Other environments leave Google Analytics disabled unless that variable is
  configured explicitly.
- Monthly, package, and resume crawls are started by systemd one-shot services
  and use the same mounted `db/` and `log/` directories as the web app.
- `/internal/jobs` reflects SQLite state from that shared app database, so stale
  package sections usually mean the package crawl is still running, the process
  died and left scans in `processing`, or the last package run failed while work
  remained pending.

## Runtime Parity

Production, CI, and the lockfile are expected to use the same Ruby patch
runtime:

- `.ruby-version`: `4.0.5`
- `Gemfile.lock` Ruby version: `ruby 4.0.5p0`
- GitHub Actions `ruby/setup-ruby`: `4.0.5`
- Docker base image: `docker.io/library/ruby:4.0.5-slim-bookworm`

The Docker base image is pinned to the Ruby patch version and Debian variant
rather than the floating `ruby:4.0-slim` tag. Update it when the project moves to
a newer stable Ruby patch release; update `.ruby-version`, `Gemfile.lock`, CI,
this document, and the container smoke test in the same change. Keep the
trailing Debian variant explicit so production does not silently move between
Debian releases.

The production image creates an `app` user with UID/GID `1000`. Systemd Podman
units also pass `--user=1000:1000`, so bind-mounted production directories owned
by the `ciembor` account remain writable without running the application as root.
The container root filesystem is read-only in production units. Runtime writes
are intentionally limited to:

- `/app/db`: SQLite database and publication backup data through the production
  `db/` bind mount.
- `/app/log`: application logs through the production `log/` bind mount.
- `/app/tmp`: ephemeral per-container tmpfs for Rack/Ruby temporary files,
  `HOME`, `TMPDIR`, and Bundler runtime config.

The CI container smoke test creates disposable `db` and `log` mounts and checks
that the container can serve `/healthz` while running as a non-root user.

## Systemd Hardening

The Podman-backed web, Discord bot, monthly, package, manual crawl, and resume
units harden the container runtime with bounded memory/CPU/PID settings,
`--user=1000:1000`, `--read-only`, and a restricted tmpfs at `/app/tmp`.
Unit-level sandboxing is intentionally lighter for these services because the
host-side systemd process must still start Podman and manage container cleanup.

The host-only alert and monitor services do not start containers, so they use
systemd sandboxing directly: `NoNewPrivileges`, `PrivateTmp`,
`ProtectSystem=strict`, `ProtectHome=read-only`, `RestrictSUIDSGID`, and
`LockPersonality`. Their `ReadWritePaths` are limited to the app `tmp/` and/or
`log/` directories required by the scripts.
