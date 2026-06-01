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
- nginx terminates TLS and protects `/internal/*` with Basic Auth before those
  requests reach the Rack app. The htpasswd file lives outside the repository at
  `/etc/nginx/.htpasswd-polish-open-source-rank`; use
  [deploy/nginx-polish-open-source-rank-internal.conf](../deploy/nginx-polish-open-source-rank-internal.conf)
  as the expected server block snippet.
- Monthly, package, and resume crawls are started by systemd one-shot services
  and use the same mounted `db/` and `log/` directories as the web app.
- `/internal/jobs` reflects SQLite state from that shared app database, so stale
  package sections usually mean the package crawl is still running, the process
  died and left scans in `processing`, or the last package run failed while work
  remained pending.
