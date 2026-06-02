# Crawl Jobs

## Monthly Job

Run the previous calendar month:

```sh
bin/monthly_rankings
```

Run a specific month:

```sh
bin/monthly_rankings --month 2026-04
bin/monthly_rankings --month 2026-04 --refresh
bin/monthly_rankings --month 2026-04 --use-stars-diff
```

The monthly job favors stability over speed:

- It sleeps between requests via `REQUESTS_PER_MINUTE`.
- It honors `Retry-After`.
- It sleeps until `X-RateLimit-Reset` before consuming the final primary GitHub
  request.
- It retries 403, 429, and 5xx responses with backoff.
- It stores candidate status in SQLite so failed runs can be resumed.

For GitHub repositories, monthly `stargazers_count` is historical at the period
end and `monthly_stars_delta` counts stars gained inside that calendar month.
For platforms without dated star history, repository stars stay the value
observed during the monthly crawl and `monthly_stars_delta` falls back to `0`.

By default, monthly star deltas are fetched from source history for the
requested calendar month. `--use-stars-diff` uses the difference between the
current observation and the previous stored monthly snapshot instead.

Production uses
[deploy/polish-open-source-rank-monthly.timer](../deploy/polish-open-source-rank-monthly.timer).
The application flow and collaborator boundaries are documented in
[Monthly Snapshot Architecture](monthly-snapshot.md).

## Package Job

Run package rankings for the previous calendar month:

```sh
bin/package_rankings
```

Run a specific package snapshot:

```sh
bin/package_rankings --period 2026-04
bin/package_rankings --period 2026-04 --ecosystem npm --repository-limit 5000 --scan-limit 5000 --manifest-limit 10000 --registry-limit 10000
```

The package job is intentionally separate from `bin/monthly_rankings`:

- It uses the same SQLite database and public repository snapshot as the web
  app.
- It shares the crawl job tracking table, so interrupted runs are resumed by
  `bin/resume_crawls`.
- It scans package manifests without executing repository code.
- It stores missing registry metrics as `nil`, and the public UI renders those
  values as `n/a`.
- It applies per-registry request limits from
  `*_REGISTRY_REQUESTS_PER_MINUTE`.

Package crawl limits are stage-specific:

- `--repository-limit` controls how many ranked repositories are enqueued.
- `--scan-limit` controls how many retryable repository scans run.
- `--manifest-limit` controls how many parsed manifests are resolved to registry
  packages.
- `--registry-limit` controls how many registry packages are fetched.
- `--limit` remains a shorthand for small local runs and applies the same value
  to all four stages.

Supported package ecosystems in the current registry fetcher are npm, RubyGems,
crates.io, PyPI, Hex, Packagist, Go, Homebrew, NuGet, Maven Central,
Terraform/OpenTofu modules, Conan, vcpkg, SwiftPM, pub.dev, APT/Debian, RPM,
and Nix. Registry download metrics are stored only when a reliable source
exists. PyPI, Go, Maven, Terraform/OpenTofu, Conan, vcpkg, SwiftPM, pub.dev,
APT/Debian, RPM, and Nix keep unavailable download metrics as `nil` and can
still be ranked by linked repository stars and monthly star trend.

Production uses
[deploy/polish-open-source-rank-packages.timer](../deploy/polish-open-source-rank-packages.timer),
scheduled for midnight on the first day of each month. The package service
starts after the monthly ranking service and requires the monthly snapshot to be
complete before publishing package rankings.

## Production Job Topology

Periodic jobs are systemd one-shot services that run short-lived Podman
containers against the same mounted `db/` and `log/` directories as the web
app.

- `polish-open-source-rank-monthly.timer` starts
  `polish-open-source-rank-monthly.service` at midnight on the first day of
  each month.
- `polish-open-source-rank-packages.timer` starts
  `polish-open-source-rank-packages.service` at midnight on the first day of
  each month.
- Both timers use `Persistent=true`, so systemd starts a missed run after the
  host comes back.
- Both crawl services use `flock -n tmp/crawl.lock`, so only one crawl runs at
  a time.
- Crawl services run containers with the production environment file, the
  production database volume, `RACK_ENV=production`, and bounded memory/CPU
  limits.
- The web service starts `polish-open-source-rank-crawl-resume.service` after
  the app container starts. That covers deploys and host/container restarts that
  left a crawl marked as `running` or `interrupted`.

Relevant units:

- [deploy/polish-open-source-rank-monthly.service](../deploy/polish-open-source-rank-monthly.service)
- [deploy/polish-open-source-rank-monthly.timer](../deploy/polish-open-source-rank-monthly.timer)
- [deploy/polish-open-source-rank-packages.service](../deploy/polish-open-source-rank-packages.service)
- [deploy/polish-open-source-rank-packages.timer](../deploy/polish-open-source-rank-packages.timer)
- [deploy/polish-open-source-rank-crawl.service](../deploy/polish-open-source-rank-crawl.service)
- [deploy/polish-open-source-rank-crawl-resume.service](../deploy/polish-open-source-rank-crawl-resume.service)

## Restart and Resume Semantics

Every CLI crawl records a row in `crawl_job_runs` with command name, arguments,
status, attempts, timestamps, and error. Starting a crawl with the same command
and arguments reopens an unfinished row instead of creating unrelated work.

Failure behavior:

- If a monthly job receives `SIGINT` or `SIGTERM`, it marks the tracked crawl as
  `interrupted`.
- If a monthly or package job raises an exception, it marks the tracked crawl as
  `failed`.
- If the process is killed abruptly, for example by OOM or host/container loss,
  it may leave the tracked crawl as `running`.
- `polish-open-source-rank-monthly.service`,
  `polish-open-source-rank-packages.service`, and
  `polish-open-source-rank-crawl.service` use `Restart=on-failure` and retry
  after 60 seconds.
- `polish-open-source-rank-crawl-resume.service` also retries after 60 seconds,
  but lock contention on `tmp/crawl.lock` exits with code `75` and is treated as
  a non-error because another crawl is already active.
- `bin/resume_crawls` resumes tracked jobs with status `running` or
  `interrupted`.
- A manually stopped systemd service is treated as an operator action; start the
  resume service when you want to continue later.

Monthly ranking resume behavior:

- Already processed candidates and already written monthly stats are skipped.
- Retryable candidate failures can be picked up on the next attempt.
- `--refresh` intentionally reprocesses the selected period, platform, or scope.
- `--use-stars-diff` uses previous stored repository star observations instead
  of fetching monthly star history again from the source API.

Package ranking resume behavior:

- Repository scan queue insertion is idempotent.
- Repositories in `pending` or `failed` scan status are retried.
- Stale `processing` package scans are moved back to `failed` at the start of a
  package run.
- Already stored registry snapshots for the selected period are skipped unless
  `--refresh` is passed.
- `--refresh` intentionally rechecks existing manifests and overwrites or
  upserts package snapshot data for the selected period.

Package runs print a short summary with repository scan counts, detected
manifests, registry fetch statuses, and written snapshots. To repair a previous
abrupt package interruption before a manual rerun, use:

```sh
sudo podman exec -w /app polish-open-source-rank bundle exec rake crawl:repair_packages[2026-04]
```

## Server Commands

Run these from the server as `ciembor` in `/home/ciembor/polish-open-source-rank`.

The production host does not have a system `sqlite3` binary. Inspect the live
database from inside the app container through the bundled Ruby `sqlite3` gem
instead of trying `sqlite3 db/...` directly on the host.

Useful container inventory:

```sh
sudo podman ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'
```

Main production container names:

- `polish-open-source-rank`: long-lived web app container.
- `polish-open-source-rank-discord-bot`: long-lived Discord bot container.
- `polish-open-source-rank-monthly`: one-shot monthly ranking job container.
- `polish-open-source-rank-packages`: one-shot package ranking job container.
- `polish-open-source-rank-crawl`: one-shot manual monthly crawl container.
- `polish-open-source-rank-crawl-resume`: one-shot interrupted-crawl resume
  container.
- `polish-open-source-rank-packages-manual`: ad hoc manual package crawl
  container started from the documented `podman run` command.

Example database query:

```sh
ssh ciembor@maciej-ciemborowicz.eu
sudo podman exec -w /app polish-open-source-rank ruby -e 'require "bundler/setup"; require "sqlite3"; db = SQLite3::Database.new("db/polish_open_source_rank.sqlite3"); db.results_as_hash = true; puts db.execute("SELECT login FROM users LIMIT 3").map { |row| row["login"] }'
```

If you need more than a one-liner, create a short Ruby script under `/tmp` or
`/app/tmp` and run it with:

```sh
sudo podman exec -w /app polish-open-source-rank ruby /tmp/script.rb
```

Resume anything left as `running` or `interrupted`:

```sh
sudo systemctl start polish-open-source-rank-crawl-resume.service
sudo journalctl -u polish-open-source-rank-crawl-resume.service -f
```

Run the normal monthly job for the previous calendar month:

```sh
sudo systemctl start polish-open-source-rank-monthly.service
sudo journalctl -u polish-open-source-rank-monthly.service -f
```

Run the normal package job for the previous calendar month:

```sh
sudo systemctl start polish-open-source-rank-packages.service
sudo journalctl -u polish-open-source-rank-packages.service -f
```

Run a manual monthly crawl with explicit arguments through the manual crawl
service:

```sh
printf 'CRAWL_ARGS="--month 2026-04 --platform github --scope organizations"\n' > .crawl.env
sudo systemctl start polish-open-source-rank-crawl.service
sudo journalctl -u polish-open-source-rank-crawl.service -f
```

Continue the same manual monthly crawl after an interruption by starting the
resume service or by starting the same command without `--refresh`. Overwrite
and recompute it by adding `--refresh`. Add `--use-stars-diff` only when
repository star deltas should be estimated from previous stored observations
instead of fetched from source history:

```sh
printf 'CRAWL_ARGS="--month 2026-04 --platform github --scope organizations --refresh"\n' > .crawl.env
sudo systemctl start polish-open-source-rank-crawl.service
```

Run a manual package crawl with explicit arguments in a one-shot Podman
container:

```sh
sudo flock -n /home/ciembor/polish-open-source-rank/tmp/crawl.lock \
  podman run --rm --name polish-open-source-rank-packages-manual \
  --memory=2500m --memory-swap=3000m \
  --env-file /home/ciembor/polish-open-source-rank/.env.local \
  -e RACK_ENV=production -e APP_BASE_PATH=/ -e BASE_URL=https://polish-open-source.pl \
  -v /home/ciembor/polish-open-source-rank/db:/app/db \
  -v /home/ciembor/polish-open-source-rank/log:/app/log \
  localhost/polish-open-source-rank:latest \
  bundle exec ruby bin/package_rankings --period 2026-04 --ecosystem npm \
    --repository-limit 5000 --scan-limit 5000 --manifest-limit 10000 --registry-limit 10000
```

Continue a package crawl with the same command and no `--refresh`, or recompute
already stored registry snapshots with `--refresh`:

```sh
sudo flock -n /home/ciembor/polish-open-source-rank/tmp/crawl.lock \
  podman run --rm --name polish-open-source-rank-packages-manual \
  --memory=2500m --memory-swap=3000m \
  --env-file /home/ciembor/polish-open-source-rank/.env.local \
  -e RACK_ENV=production -e APP_BASE_PATH=/ -e BASE_URL=https://polish-open-source.pl \
  -v /home/ciembor/polish-open-source-rank/db:/app/db \
  -v /home/ciembor/polish-open-source-rank/log:/app/log \
  localhost/polish-open-source-rank:latest \
  bundle exec ruby bin/package_rankings --period 2026-04 --ecosystem npm \
    --repository-limit 5000 --scan-limit 5000 --manifest-limit 10000 --registry-limit 10000 --refresh
```
