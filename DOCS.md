# Polish Open Source Rank

Monthly Ruby application that builds public code-hosting rankings for Poland and selected Polish cities.

Public platform APIs do not provide portable regex search over user locations, so the sync job searches a fixed catalog of country and city variants, stores candidates, and then classifies every profile locally with regex-based matching. Interrupted runs are resumable because candidates and monthly snapshots are stored in SQLite.

Package rankings are built as a separate crawl after the monthly source ranking. The package job scans already-ranked public repositories for known manifest files, resolves package identities through registry APIs, and stores registry snapshots in the same SQLite database.

## Data Collected

- User login, name, raw location, normalized city, normalized country, public email, homepage, profile URL, avatar URL.
- User monthly stats: public repo count, total stars across owned public repositories, stars gained by those repositories during the month when the platform exposes dated star history, public activity event count during the month.
- Repository data per user: name, full name, URL, homepage, language, description, fork/archive flags.
- Repository monthly stats: current stars and stars gained during the month.
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
```

The job intentionally favors stability over speed:

- sleeps between requests via `REQUESTS_PER_MINUTE`;
- honors `Retry-After`;
- sleeps until `X-RateLimit-Reset` before consuming the final primary GitHub request;
- retries 403, 429, and 5xx responses with backoff;
- stores candidate status in SQLite so failed runs can be resumed.

Production uses the systemd timer in [deploy/polish-open-source-rank-monthly.timer](deploy/polish-open-source-rank-monthly.timer).

## Package Job

Run package rankings for the previous calendar month:

```sh
bin/package_rankings
```

Run a specific package snapshot:

```sh
bin/package_rankings --period 2026-04
bin/package_rankings --period 2026-04 --ecosystem npm --limit 100
```

The package job is deliberately separate from `bin/monthly_rankings`:

- it uses the same SQLite database and public repository snapshot as the web app;
- it shares the crawl job tracking table, so interrupted runs are resumed by `bin/resume_crawls`;
- it scans package manifests without executing repository code;
- it stores missing registry metrics as `nil`, and the public UI renders those values as `n/a`;
- it applies per-registry request limits from `*_REGISTRY_REQUESTS_PER_MINUTE`.

Supported package ecosystems in the current registry fetcher are npm, RubyGems, crates.io, PyPI, Hex, Packagist, and Go. PyPI downloads are intentionally unavailable until a reliable download source is wired in, so they are stored as `nil`.

Production uses [deploy/polish-open-source-rank-packages.timer](deploy/polish-open-source-rank-packages.timer), scheduled for `07:15` on the second day of each month. The timer starts after the monthly ranking service and both jobs use the same `tmp/crawl.lock`, so a long monthly crawl prevents package crawling from running concurrently.

Equivalent rake tasks are available for local operations:

```sh
bundle exec rake crawl:monthly[2026-04,github,organizations,false]
bundle exec rake crawl:packages[2026-04,npm,100,false]
bundle exec rake crawl:resume
bundle exec rake crawl:list
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

## Deployment

The app is deployed behind Nginx at `https://polish-open-source.pl`. Nginx is configured on the server. The application and jobs run as Podman containers via systemd:

- [deploy/polish-open-source-rank.service](deploy/polish-open-source-rank.service)
- [deploy/polish-open-source-rank-monthly.service](deploy/polish-open-source-rank-monthly.service)
- [deploy/polish-open-source-rank-monthly.timer](deploy/polish-open-source-rank-monthly.timer)
- [deploy/polish-open-source-rank-packages.service](deploy/polish-open-source-rank-packages.service)
- [deploy/polish-open-source-rank-packages.timer](deploy/polish-open-source-rank-packages.timer)

GitHub Actions runs quality checks and then calls [scripts/deploy.sh](scripts/deploy.sh). Required repository secret:

- `SSH_PRIVATE_KEY_B64`: base64-encoded private SSH key accepted for `ciembor@maciej-ciemborowicz.eu`.

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
