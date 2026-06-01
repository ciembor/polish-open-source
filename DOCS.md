# Polish Open Source Rank

Monthly Ruby application that builds public code-hosting rankings for Poland and selected Polish cities.

Public platform APIs do not provide portable regex search over user locations, so the sync job searches a fixed catalog of country and city variants, stores candidates, and then classifies every profile locally with regex-based matching. Interrupted runs are resumable because candidates and monthly snapshots are stored in SQLite.

Package rankings are built as a separate crawl after the monthly source ranking. The package job scans already-ranked public repositories for known manifest files, resolves package identities through registry APIs, and stores registry snapshots in the same SQLite database.

## Data Collected

- User login, name, raw location, normalized city, normalized country, public email, homepage, profile URL, avatar URL.
- User monthly stats: public repo count, total stars across owned public repositories, stars gained by those repositories during the month when the platform exposes dated star history, public activity event count during the month.
- Repository data per user: name, full name, URL, homepage, language, description, fork/archive flags.
- Repository monthly stats: stars and stars gained during the month.
- Organization profiles and organization repositories with the same public ranking fields.
- Package manifest data from public repositories: ecosystem, manifest path, package name, normalized package name, parser status, registry links, homepage, repository URL, and license when the manifest exposes it.
- Package registry snapshots: latest version, release timestamp when available, download metrics when available, dependent package counts when available, and dependent repository counts when available.

## Rankings

Each scope has:

- Top 10 users by total stars.
- Trending 10 users by stars gained in the month.
- Top 10 active users by public GitHub events in the month.
- Top 10 repositories by stars.
- Trending 10 repositories by stars gained in the month.
- Top 10 organizations and organization repositories.
- Package rankings per ecosystem: 30-day downloads, total downloads, and dependent package count.

Scopes are Poland plus supported Polish cities. Package rankings are country-level only and are not split by city.

## Setup

```sh
bundle install
cp .env.local.example .env.local
```

Put the GitHub token in `.env.local`. That file is ignored by git.

```env
GITHUB_TOKEN=...
GITLAB_TOKEN=...
CODEBERG_TOKEN=...
DATABASE_URL=sqlite://db/polish_open_source_rank.sqlite3
REQUESTS_PER_MINUTE=60
HTTP_OPEN_TIMEOUT=5
HTTP_READ_TIMEOUT=30
HTTP_WRITE_TIMEOUT=30
NPM_REGISTRY_REQUESTS_PER_MINUTE=30
RUBYGEMS_REGISTRY_REQUESTS_PER_MINUTE=20
CRATES_REGISTRY_REQUESTS_PER_MINUTE=10
PYPI_REGISTRY_REQUESTS_PER_MINUTE=20
HEX_REGISTRY_REQUESTS_PER_MINUTE=20
PACKAGIST_REGISTRY_REQUESTS_PER_MINUTE=20
GO_REGISTRY_REQUESTS_PER_MINUTE=20
BASE_URL=https://polish-open-source.pl
APP_BASE_PATH=/
```

`GITLAB_TOKEN` and `CODEBERG_TOKEN` are optional for public API access, but recommended for more stable monthly runs.

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

The job intentionally favors stability over speed:

- sleeps between requests via `REQUESTS_PER_MINUTE`;
- honors `Retry-After`;
- sleeps until `X-RateLimit-Reset` before consuming the final primary GitHub request;
- retries 403, 429, and 5xx responses with backoff;
- stores candidate status in SQLite so failed runs can be resumed.

For GitHub repositories, monthly `stargazers_count` is historical at the period end and
`monthly_stars_delta` counts stars gained inside that calendar month. For platforms
without dated star history, repository stars stay the value observed during the
monthly crawl and `monthly_stars_delta` falls back to `0`.

Languages and packages join repository monthly stats on the same `period_start`, so
published monthly views do not mix April package or language snapshots with March
repository star totals.

By default, monthly star deltas are fetched from source history for the requested
calendar month. `--use-stars-diff` uses the difference between the current observation
and the previous stored monthly snapshot instead.

Production uses the systemd timer in [deploy/polish-open-source-rank-monthly.timer](deploy/polish-open-source-rank-monthly.timer).

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

The package job is deliberately separate from `bin/monthly_rankings`:

- it uses the same SQLite database and public repository snapshot as the web app;
- it shares the crawl job tracking table, so interrupted runs are resumed by `bin/resume_crawls`;
- it scans package manifests without executing repository code;
- it stores missing registry metrics as `nil`, and the public UI renders those values as `n/a`;
- it applies per-registry request limits from `*_REGISTRY_REQUESTS_PER_MINUTE`.

Package crawl limits are stage-specific. `--repository-limit` controls how many ranked repositories are enqueued, `--scan-limit` controls how many retryable repository scans run, `--manifest-limit` controls how many parsed manifests are resolved to registry packages, and `--registry-limit` controls how many registry packages are fetched. `--limit` remains a shorthand for small local runs and applies the same value to all four stages.

Supported package ecosystems in the current registry fetcher are npm, RubyGems, crates.io, PyPI, Hex, Packagist, Go, Homebrew, NuGet, Maven Central, Terraform/OpenTofu modules, Conan, vcpkg, SwiftPM, pub.dev, APT/Debian, RPM, and Nix. Registry download metrics are stored only when a reliable source exists; PyPI, Go, Maven, Terraform/OpenTofu, Conan, vcpkg, SwiftPM, pub.dev, APT/Debian, RPM, and Nix keep unavailable download metrics as `nil` and can still be ranked by linked repository stars and monthly star trend.

Production uses [deploy/polish-open-source-rank-packages.timer](deploy/polish-open-source-rank-packages.timer), scheduled for midnight on the first day of each month. The package service starts after the monthly ranking service and requires the monthly snapshot to be complete before publishing package rankings.

Equivalent rake tasks are available for local operations:

```sh
bundle exec rake crawl:monthly[2026-04,github,organizations,false]
bundle exec rake crawl:packages[2026-04,npm,100,false]
bundle exec rake crawl:packages[2026-04,npm,,false,5000,5000,10000,10000]
bundle exec rake crawl:repair_packages[2026-04]
bundle exec rake crawl:resume
bundle exec rake crawl:list
```

## Production Job Operations

Periodic jobs are systemd one-shot services that run short-lived Podman containers against the same mounted `db/` and `log/` directories as the web app.

- `polish-open-source-rank-monthly.timer` starts `polish-open-source-rank-monthly.service` at midnight on the first day of each month.
- `polish-open-source-rank-packages.timer` starts `polish-open-source-rank-packages.service` at midnight on the first day of each month.
- Both timers use `Persistent=true`, so systemd starts a missed run after the host comes back.
- Both crawl services use `flock -n tmp/crawl.lock`, so only one crawl runs at a time.
- Crawl services run containers with the production env file, the production database volume, `RACK_ENV=production`, and bounded memory/CPU limits.
- The web service starts `polish-open-source-rank-crawl-resume.service` after the app container starts. This covers deploys and host/container restarts that left a crawl marked as `running` or `interrupted`.

The relevant units are:

- [deploy/polish-open-source-rank-monthly.service](deploy/polish-open-source-rank-monthly.service)
- [deploy/polish-open-source-rank-monthly.timer](deploy/polish-open-source-rank-monthly.timer)
- [deploy/polish-open-source-rank-packages.service](deploy/polish-open-source-rank-packages.service)
- [deploy/polish-open-source-rank-packages.timer](deploy/polish-open-source-rank-packages.timer)
- [deploy/polish-open-source-rank-crawl.service](deploy/polish-open-source-rank-crawl.service)
- [deploy/polish-open-source-rank-crawl-resume.service](deploy/polish-open-source-rank-crawl-resume.service)

### Restart and Resume Semantics

Every CLI crawl records a row in `crawl_job_runs` with command name, arguments, status, attempts, timestamps, and error. Starting a crawl with the same command and arguments reopens an unfinished row instead of creating unrelated work.

What happens when something fails:

- If a monthly job receives `SIGINT` or `SIGTERM`, it marks the tracked crawl as `interrupted`.
- If a monthly or package job raises an exception, it marks the tracked crawl as `failed`.
- If the process is killed abruptly, for example by OOM or host/container loss, it may leave the tracked crawl as `running`.
- `polish-open-source-rank-monthly.service`, `polish-open-source-rank-packages.service`, and `polish-open-source-rank-crawl.service` use `Restart=on-failure` and retry after 60 seconds.
- `polish-open-source-rank-crawl-resume.service` also retries after 60 seconds, but lock contention on `tmp/crawl.lock` exits with code `75` and is treated as a non-error because another crawl is already active.
- `bin/resume_crawls` resumes tracked jobs with status `running` or `interrupted`.
- A manually stopped systemd service is treated as an operator action; start the resume service when you want to continue later.

The monthly ranking job resumes at the data level:

- already processed candidates and already written monthly stats are skipped;
- retryable candidate failures can be picked up on the next attempt;
- `--refresh` intentionally reprocesses the selected period/platform/scope.
- `--use-stars-diff` uses previous stored repository star observations instead of fetching monthly
  star history again from the source API.

The package ranking job also resumes at the data level:

- repository scan queue insertion is idempotent;
- repositories in `pending` or `failed` scan status are retried;
- stale `processing` package scans are moved back to `failed` at the start of a package run;
- already stored registry snapshots for the selected period are skipped unless `--refresh` is passed;
- `--refresh` intentionally rechecks existing manifests and overwrites/upserts package snapshot data for the selected period.

Package runs print a short summary with repository scan counts, detected manifests, registry fetch statuses, and written snapshots. To repair a previous abrupt package interruption before a manual rerun, use:

```sh
sudo podman exec -w /app polish-open-source-rank bundle exec rake crawl:repair_packages[2026-04]
```

### Server Commands

Run these from the server as `ciembor` in `/home/ciembor/polish-open-source-rank`.

The production host does not have a system `sqlite3` binary. When you need to inspect the live database, query it from inside the app container through the bundled Ruby `sqlite3` gem instead of trying `sqlite3 db/...` on the host.

Useful container inventory:

```sh
sudo podman ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'
```

The main container names used by production are:

- `polish-open-source-rank`: long-lived web app container.
- `polish-open-source-rank-discord-bot`: long-lived Discord bot container.
- `polish-open-source-rank-monthly`: one-shot monthly ranking job container.
- `polish-open-source-rank-packages`: one-shot package ranking job container.
- `polish-open-source-rank-crawl`: one-shot manual monthly crawl container.
- `polish-open-source-rank-crawl-resume`: one-shot interrupted-crawl resume container.
- `polish-open-source-rank-packages-manual`: ad hoc manual package crawl container started from the documented `podman run` command.

Example:

```sh
ssh ciembor@maciej-ciemborowicz.eu
sudo podman exec -w /app polish-open-source-rank ruby -e 'require "bundler/setup"; require "sqlite3"; db = SQLite3::Database.new("db/polish_open_source_rank.sqlite3"); db.results_as_hash = true; puts db.execute("SELECT login FROM users LIMIT 3").map { |row| row["login"] }'
```

If you need more than a one-liner, create a short Ruby script under `/tmp` or `/app/tmp` and run it with `sudo podman exec -w /app polish-open-source-rank ruby /tmp/script.rb`.

When `/internal/jobs` shows `package repository scans` as `failed` and `stale`, check production in this order:

```sh
ssh ciembor@maciej-ciemborowicz.eu
sudo systemctl status polish-open-source-rank-packages.service polish-open-source-rank-crawl-resume.service --no-pager
sudo journalctl -u polish-open-source-rank-packages.service -u polish-open-source-rank-crawl-resume.service -n 200 --no-pager
sudo podman exec -w /app polish-open-source-rank bundle exec rake crawl:list
```

Interpretation:

- active `polish-open-source-rank-packages.service`: the backlog may still be draining;
- failed package service plus pending package scans: the last package crawl aborted before it finished the queue;
- old rows left in `processing`: repair them with `rake crawl:repair_packages[...]` before rerunning or resuming;
- `crawl:list` is the fastest way to confirm whether the tracked package job is `running`, `interrupted`, `failed`, or already reopened by `resume_crawls`.

Inspect timers and recent job logs:

```sh
systemctl list-timers 'polish-open-source-rank-*'
sudo journalctl -u polish-open-source-rank-monthly.service -n 200 --no-pager
sudo journalctl -u polish-open-source-rank-packages.service -n 200 --no-pager
sudo journalctl -u polish-open-source-rank-crawl-resume.service -n 200 --no-pager
```

List tracked crawl jobs from the running app container:

```sh
sudo podman exec -w /app polish-open-source-rank bundle exec rake crawl:list
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

Run a manual monthly crawl with explicit arguments through the manual crawl service:

```sh
printf 'CRAWL_ARGS="--month 2026-04 --platform github --scope organizations"\n' > .crawl.env
sudo systemctl start polish-open-source-rank-crawl.service
sudo journalctl -u polish-open-source-rank-crawl.service -f
```

Continue the same manual monthly crawl after an interruption by starting the resume service or by starting the same command without `--refresh`. Overwrite/recompute it by adding `--refresh`; add `--use-stars-diff` only when repository star deltas should be estimated from previous stored observations instead of fetched from source history:

```sh
printf 'CRAWL_ARGS="--month 2026-04 --platform github --scope organizations --refresh"\n' > .crawl.env
sudo systemctl start polish-open-source-rank-crawl.service
```

Run a manual package crawl with explicit arguments in a one-shot Podman container:

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

Continue a package crawl with the same command and no `--refresh`, or recompute already stored registry snapshots with `--refresh`:

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

## Web App

```sh
bin/server
```

Routes:

- `/` for Poland;
- `/locations/krakow`, `/locations/wroclaw`, `/locations/warszawa`, `/locations/gdansk`, `/locations/poznan`, `/locations/szczecin`, `/locations/lodz`;
- `/packages` for package ecosystems;
- `/latest/packages/npm`, `/latest/packages/npm/top`, `/latest/packages/npm/downloads`, `/latest/packages/npm/dependents`;
- `/healthz`.

The HTML uses semantic sections, tables, canonical URLs, meta descriptions, and JSON-LD dataset metadata.

Public pages are intentionally cacheable by URL. Polish pages use the default unprefixed routes, English pages use `/en/...`, and both variants expose self-canonical and `hreflang` links. Do not make shared cache depend on the `locale` cookie; the cookie is only a user preference for redirects and must not be the CDN cache key for indexed pages.

Recommended edge rules:

- cache anonymous `GET`/`HEAD` HTML for public ranking, profile, language, package, and badge routes;
- bypass shared cache whenever the request has the signed session cookie `polish_open_source_rank.session`;
- vary public cached HTML by path and query string, not by arbitrary cookies;
- keep `/auth/*`, `/logout`, `/internal/*`, and responses with `Cache-Control: private` or `no-store` out of shared cache;
- rate-limit `/auth/*`, `/badges/*`, `/internal/*`, and ranking detail bursts before the Rack app;
- do not rate-limit normal search crawler access to indexed PL/EN pages; if crawler-specific limits are needed, verify them at the edge with reverse DNS instead of trusting `User-Agent`.

## Deployment

The app is deployed behind Nginx at `https://polish-open-source.pl`. Nginx is configured on the server. The application and jobs run as Podman containers via systemd:

- [deploy/polish-open-source-rank.service](deploy/polish-open-source-rank.service)
- [deploy/polish-open-source-rank-monthly.service](deploy/polish-open-source-rank-monthly.service)
- [deploy/polish-open-source-rank-monthly.timer](deploy/polish-open-source-rank-monthly.timer)
- [deploy/polish-open-source-rank-packages.service](deploy/polish-open-source-rank-packages.service)
- [deploy/polish-open-source-rank-packages.timer](deploy/polish-open-source-rank-packages.timer)
- [deploy/polish-open-source-rank-crawl.service](deploy/polish-open-source-rank-crawl.service)
- [deploy/polish-open-source-rank-crawl-resume.service](deploy/polish-open-source-rank-crawl-resume.service)

GitHub Actions runs quality checks and then calls [scripts/deploy.sh](scripts/deploy.sh). Required repository secret:

- `SSH_PRIVATE_KEY_B64`: base64-encoded private SSH key accepted for `ciembor@maciej-ciemborowicz.eu`.

The `Deploy to server` workflow supports two actions:

- normal `deploy` on every push to `master`;
- manual `rollback` through `workflow_dispatch`, limited to swapping back to the immediately previous image.

The deploy script does not touch running monthly or package jobs. It restarts only the
web and Discord bot services, then waits for built-in smoke checks on local `/healthz`
plus public `/healthz`, `/latest`, and `/en/latest` before treating the release as healthy.

Operational shape on the live host:

- the production host is reached as `ciembor@maciej-ciemborowicz.eu`;
- the app checkout lives in `/home/ciembor/polish-open-source-rank`;
- the web app runs in the `polish-open-source-rank` Podman container;
- monthly, package, and resume crawls are started by `systemd` one-shot services and use the same mounted `db/` and `log/` directories as the web app;
- `/internal/jobs` reflects SQLite state from that shared app database, so `stale` package sections usually mean the package crawl is still running, the process died and left scans in `processing`, or the last package run failed while work remained pending.

## Quality

```sh
bin/quality
```

This runs RuboCop, Reek, and RSpec. SimpleCov enforces 100% line coverage for `lib/**/*.rb`.

Mutation checks are available on demand through [Mutant](https://github.com/mbj/mutant):

```sh
bin/mutant-changed
```

That command only mutation-tests staged Ruby production subjects. Full Mutant output is written to `tmp/mutant-last.log`; the terminal output stays short enough for agent-driven review.

Pre-commit hooks live in `.githooks/pre-commit`. This checkout is configured with:

```sh
git config core.hooksPath .githooks
```
