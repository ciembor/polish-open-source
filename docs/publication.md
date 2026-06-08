# Public Snapshot Publication

## Published Month Definition

A month becomes public only when it has a `published` or `superseded` record in
`public_snapshot_publications`. `published` is the current `latest`, while
`superseded` is an older month that can still be linked in history, sitemaps,
canonical URLs, and `hreflang`.

A snapshot can be published when:

- the monthly run in `sync_runs` has status `finished`;
- public data exists for users, repositories, organizations, and organization
  repositories;
- the month has no package crawl runs with a status other than `finished`.

Languages are derived from public repositories, so they are published together
with repository stats. Badges, profiles, rankings, packages, languages,
sitemaps, canonical URLs, and `hreflang` use only the published month or the
`latest` alias.

## Historical Metric Semantics

For GitHub, public repositories and organization repositories store two distinct
monthly metrics:

- `stargazers_count`: the number of stars at the end of the published month;
- `monthly_stars_delta`: only the stars gained in that month according to
  `starred_at`.

GitLab and Codeberg do not expose dated star history today, so:

- `stargazers_count` remains the value observed during the monthly crawl;
- `monthly_stars_delta` is explicitly stored as `0` instead of pretending to be
  a historical diff.

Languages and packages do not recalculate these values independently. Both
sections join `repository_monthly_stats` or
`organization_repository_monthly_stats` on the same `period_start`, so a
published month does not mix repository data from another period.

## Historical Star Backfill Plan

Backfill applies only to GitHub months that were computed before historical star
snapshots were introduced or that were run with `--use-stars-diff`.

Cost estimation starts with a simple lower bound:

- at least one stargazer-history request per repository and month;
- minimum time of `repo_count / REQUESTS_PER_MINUTE`;
- with the current `REQUESTS_PER_MINUTE=60`, a local snapshot with `300`
  repositories gives a lower bound of about `5` minutes for one GitHub month,
  before extra history pages, retries, and rate-limit waits.

Recommended order:

1. Start with the oldest published month missing historical stars.
2. Run one month at a time, with resume support from SQLite job status.
3. Pause further months if Sentry shows higher retries, 5xx responses, or
   latency.

## Promotion

`bin/publish_snapshot YYYY-MM` performs:

1. `staged` for the requested month;
2. publication prerequisite verification;
3. a WAL checkpoint;
4. a SQLite file backup to `db/publication_backups`;
5. an atomic switch from the current `published` month to `superseded`, and the
   new month to `published`.

Rollback does not touch working data:

```sh
bin/publish_snapshot --rollback
```

Rollback marks the current snapshot as `rolled_back` and restores the previous
`published` snapshot.

## Cloudflare Cache Purge

Monthly publication changes public rankings, profiles, language pages, package
pages, badges, sitemap-visible URLs, canonical URLs, and `latest` aliases
together. After a successful publish or rollback, `bin/publish_snapshot` purges
Cloudflare with `purge_everything` when both variables are configured:

```sh
CLOUDFLARE_ZONE_ID=<zone-id>
CLOUDFLARE_API_TOKEN=<api-token>
```

The API token must have `Zone -> Cache Purge -> Purge` permission scoped to the
`polish-open-source.pl` zone. If either variable is missing, publication still
succeeds and logs that Cloudflare purge was skipped. If the Cloudflare API call
fails, publication also stays successful and logs the failure; the origin data
and ETags are already updated, while edge cache may serve stale content until
TTL expiry or a manual purge.

Manual verification:

```sh
curl -fsS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  https://api.cloudflare.com/client/v4/user/tokens/verify
```

Manual emergency purge for a single stale URL:

```sh
curl -fsS -X POST "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/purge_cache" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -H "Content-Type: application/json" \
  --data '{"files":["https://polish-open-source.pl/badges/repositories/github/ciembor/agent-rules-books.svg"]}'
```

## Separate Snapshot for Public Reads

By default, the web app serves public pages from `DATABASE_URL` to stay
compatible with the existing job flow. After preparing a separate file, set:

```sh
PUBLIC_DATABASE_URL=sqlite://db/public.sqlite3
```

Public read models then open that file with `PRAGMA query_only = ON`, while user
actions and job state continue writing to `DATABASE_URL`.
