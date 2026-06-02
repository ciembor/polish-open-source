# Public performance checks

## SLO

The public read path is considered safe for the current single-web-process SQLite
architecture when the same profile passes on the target host:

- p95 latency: `<= 500 ms`
- p99 latency: `<= 1500 ms`
- 5xx rate: `<= 0.1%`
- rate limited responses during the test: `0`
- CPU: sustained web container CPU below `80%`
- memory: sustained web container memory below `80%`

Use `scripts/server-health-snapshot.sh` immediately before and after a run to keep
CPU and memory evidence next to the latency report.

## Load Profile

Run the public profile against staging or production:

```sh
BASE_URL=https://polish-open-source.pl \
  CONCURRENCY=4 \
  DURATION=60 \
  scripts/public_load_test.rb > log/public-load-after.json
```

The profile covers `/latest`, detailed rankings, profiles, organizations,
languages, packages, and a user badge. It does not send authenticated requests
and it fails if any `429` is returned. That keeps the scenario from silently
training operators to raise crawler-visible rate limits or bypass them with fake
client addresses.

If `wrk` is available, the equivalent request mix is:

```sh
wrk -t2 -c4 -d60s -s scripts/public-wrk.lua https://polish-open-source.pl
```

Use the Ruby runner for the pass/fail SLO gate because it reports p95, p99, 5xx,
and `429` counts as structured JSON.

For a before/after comparison, run the same command with the same `BASE_URL`,
`CONCURRENCY`, `DURATION`, source IP, and published snapshot before and after a
change. Compare `requests_per_second`, `p95_ms`, `p99_ms`, `server_error_rate`,
and `rate_limited_responses`.

The conservative safe level for this milestone is the default profile above:
4 concurrent anonymous clients for 60 seconds with all SLO checks passing. Raise
the profile only after the same report and server health snapshot stay inside the
budgets.

## Query Plans

Collect representative public SQLite query plans from the public read database:

```sh
PUBLIC_DATABASE_URL=sqlite://db/public.sqlite3 scripts/public_query_plans.rb > log/public-query-plans.md
```

For the default database:

```sh
scripts/public_query_plans.rb --database db/polish_open_source_rank.sqlite3 > log/public-query-plans.md
```

The report covers latest period resolution, people, repository and organization
rankings, profile/badge lookups, language index, and package ranking. Add an
index only when this report shows a full scan on a production-sized database for
a path that is slow in the load report.

Local smoke output for the current schema showed index-backed lookups for the
representative ranking, profile, badge, language, and package queries. Temporary
B-trees remain for group/order tie-breakers; those are expected until a
production-sized report shows they dominate latency. No new index was added in
this milestone because the available plans did not prove one was needed.

## Gzip Decision

`Rack::Deflater` stays enabled for now. It is already covered by request tests
and reduces public HTML/SVG transfer without changing cache keys. Move gzip to
nginx/CDN only if the load report plus server health snapshot show web CPU as
the bottleneck while SQLite query plans remain index-backed.

## Negative Cache Decision

Only stable public 404s are short-cached for 30 seconds: unknown location slugs
that match ranking routes and unsupported package metric/ecosystem combinations.
Data-dependent misses such as missing profiles, repositories, organizations,
languages, package ecosystem pages, and badges are not negative-cached because a
user action or the next published snapshot can make them valid.

## Production Limits

The current production shape stays intentionally conservative:

- one host;
- one web container behind nginx;
- one shared SQLite database for web, monthly, packages, and user actions;
- cache in front of the app, keyed by URL rather than locale cookie.

Do not add systemd socket activation, blue-green deploys, or a second web worker
until the read-only public snapshot path is stable in production. With the current
shared SQLite write path, more parallel web capacity can increase lock contention
instead of reducing user-visible downtime.

## Spike Response

When public traffic spikes, use this order:

1. Keep indexed public PL and EN pages cacheable by URL; do not add a global `noindex`.
2. Verify Cloudflare is respecting origin cache headers for anonymous public HTML and badges, including `stale-if-error`.
3. Increase CDN or nginx cache aggressiveness for `/latest`, `/en/latest`, rankings, profiles, languages, packages, and badges.
4. Tighten temporary rate limits on `/auth/*`, `/internal/*`, and other expensive non-indexed paths before indexed ranking pages.
5. If the app still needs protection, publish a static status page on a separate non-indexed operational path instead of replacing indexed public pages.
