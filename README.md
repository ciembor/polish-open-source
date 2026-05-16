# Polish GitHub Rank

Monthly Ruby application that builds GitHub rankings for Poland and selected Polish cities.

The GitHub API does not provide regex search over user locations, so the sync job searches a fixed catalog of country and city variants, stores candidates, and then classifies every profile locally with regex-based matching. Interrupted runs are resumable because candidates and monthly snapshots are stored in SQLite.

## Data Collected

- GitHub user login, name, raw location, normalized city, normalized country, public email, homepage, profile URL, avatar URL.
- User monthly stats: public repo count, total stars across owned public repositories, stars gained by those repositories during the month, public activity event count during the month.
- Repository data per user: name, full name, URL, homepage, language, description, fork/archive flags.
- Repository monthly stats: current stars and stars gained during the month.

## Rankings

Each scope has:

- Top 10 users by total stars.
- Trending 10 users by stars gained in the month.
- Top 10 active users by public GitHub events in the month.
- Top 10 repositories by stars.
- Trending 10 repositories by stars gained in the month.

Scopes are Poland plus Kraków, Wrocław, Warszawa, Gdańsk, Poznań, Szczecin, and Łódź.

## Setup

```sh
bundle install
cp .env.local.example .env.local
```

Put the GitHub token in `.env.local`. That file is ignored by git.

```env
GITHUB_TOKEN=...
DATABASE_URL=sqlite://db/polish_github_rank.sqlite3
REQUESTS_PER_MINUTE=25
BASE_URL=https://example.com
```

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
- sleeps until `X-RateLimit-Reset` when the primary GitHub limit is exhausted;
- retries 403, 429, and 5xx responses with backoff;
- stores candidate status in SQLite so failed runs can be resumed.

Example cron entry is in [config/cron.example](config/cron.example).

## Web App

```sh
bin/server
```

Routes:

- `/` for Poland;
- `/locations/krakow`, `/locations/wroclaw`, `/locations/warszawa`, `/locations/gdansk`, `/locations/poznan`, `/locations/szczecin`, `/locations/lodz`;
- `/healthz`.

The HTML uses semantic sections, tables, canonical URLs, meta descriptions, and JSON-LD dataset metadata.

## Quality

```sh
bin/quality
```

This runs RuboCop, Reek, and RSpec. SimpleCov enforces 100% line coverage for `lib/**/*.rb`.

Pre-commit hooks live in `.githooks/pre-commit`. This checkout is configured with:

```sh
git config core.hooksPath .githooks
```
