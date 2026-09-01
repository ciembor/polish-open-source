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

Public repositories and organization repositories store two distinct monthly
metrics:

- `stargazers_count`: the number of stars observed during the monthly crawl;
- `monthly_stars_delta`: the positive difference between that observation and
  the previous stored monthly observation.

Repositories without a previous monthly observation get `0` for
`monthly_stars_delta`. This keeps the metric conservative without depending on
dated stargazer lists, which are not available consistently across platforms
and are restricted by GitHub for repositories the token does not administer.

Languages and packages do not recalculate these values independently. Both
sections join `repository_monthly_stats` or
`organization_repository_monthly_stats` on the same `period_start`, so a
published month does not mix repository data from another period.

## Promotion

`bin/publish_snapshot YYYY-MM` performs:

1. `staged` for the requested month;
2. publication prerequisite verification;
3. a WAL checkpoint;
4. a SQLite file backup to `db/publication_backups`;
5. an atomic switch from the current `published` month to `superseded`, and the
   new month to `published`;
6. an atomic refresh of `PUBLIC_DATABASE_URL`, when it points at a separate
   SQLite file.

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
compatible with local development and tests. Production sets:

```sh
PUBLIC_DATABASE_URL=sqlite://db/public.sqlite3
```

Public read models then open that file with `PRAGMA query_only = ON`, while
crawls, job state, and the primary user-action write path continue writing to
`DATABASE_URL`.

`bin/publish_snapshot` refreshes the public database after successful publish or
rollback. The production publish service restarts the web container after a
successful publish so existing SQLite connections reopen the atomically replaced
file. `bin/publish_snapshot --refresh-public-database` performs only the atomic
SQLite copy from the working database to `PUBLIC_DATABASE_URL`; deployment uses
that command before restarting the web container so the read-only public file
exists before the web app switches to it.
