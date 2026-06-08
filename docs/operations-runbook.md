# Operations runbook

Production observability is centered on Sentry plus the existing uptime and host
health monitors.

## Sentry setup

Set these variables in `/home/ciembor/polish-open-source-rank/.env.local`:

- `SENTRY_DSN`
- `SENTRY_ENVIRONMENT=production`
- `SENTRY_RELEASE=<git-sha-or-release-id>`
- `SENTRY_TRACES_SAMPLE_RATE=0.05`

Configure Sentry alerts for:

- new or regressed exceptions,
- HTTP 5xx growth,
- p95 transaction latency growth,
- failed or missed `monthly-rankings` check-ins,
- failed or missed `package-rankings` check-ins,
- custom events tagged with `monitor=production-alert`.

The host alert timer also reads these optional thresholds from
`/home/ciembor/polish-open-source-rank/.env.local`:

- `PRODUCTION_ALERT_JOB_STALE_MINUTES=30`
- `PRODUCTION_ALERT_LOG_WINDOW_MINUTES=10`
- `PRODUCTION_ALERT_HTTP_5XX_THRESHOLD=5`
- `PRODUCTION_ALERT_HTTP_MIN_REQUESTS=20`
- `PRODUCTION_ALERT_P95_LATENCY_MS_THRESHOLD=1000`
- `PRODUCTION_ALERT_SQLITE_RETRY_THRESHOLD=10`

## Cloudflare cache purge

Set these variables in `/home/ciembor/polish-open-source-rank/.env.local`:

- `CLOUDFLARE_ZONE_ID`
- `CLOUDFLARE_API_TOKEN`

The token must be scoped to the `polish-open-source.pl` zone with
`Zone -> Cache Purge -> Purge`. Keep it out of commits and rotate it if it is
ever pasted into chat, logs, or a shell history that other people can read.

Verify a token without printing it:

```sh
curl -fsS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  https://api.cloudflare.com/client/v4/user/tokens/verify
```

Verify purge permission with a narrow URL purge before relying on automatic
monthly purges:

```sh
curl -fsS -X POST "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/purge_cache" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -H "Content-Type: application/json" \
  --data '{"files":["https://polish-open-source.pl/healthz"]}'
```

`bin/publish_snapshot` uses `purge_everything` after successful monthly publish
and rollback because those actions update public pages and badges across many
routes. If a public badge or page is stale, first compare Cloudflare and origin:

```sh
curl -I https://polish-open-source.pl/badges/repositories/github/ciembor/agent-rules-books.svg
ssh ciembor@maciej-ciemborowicz.eu \
  'curl -sS -I http://127.0.0.1:9293/badges/repositories/github/ciembor/agent-rules-books.svg'
```

If origin is correct and Cloudflare is stale, purge Cloudflare. If origin is
wrong, inspect publication data before purging CDN cache.

## Production session secret

`SESSION_SECRET` in `/home/ciembor/polish-open-source-rank/.env.local` must be
at least 64 characters. Generate a value with:

```sh
ruby -rsecurerandom -e 'puts SecureRandom.hex(32)'
```

## Internal operations access

`/internal/*` is protected by application Basic Auth. Set these variables in
`/home/ciembor/polish-open-source-rank/.env.local`:

- `INTERNAL_BASIC_AUTH_USERNAME`
- `INTERNAL_BASIC_AUTH_PASSWORD`

`INTERNAL_BASIC_AUTH_PASSWORD` must be at least 32 characters. Generate a value
with:

```sh
ruby -rsecurerandom -e 'puts SecureRandom.hex(24)'
```

## Deploy

1. Push `master`.
2. Confirm GitHub Actions quality passes.
3. Confirm the `Deploy or rollback` step finishes successfully in GitHub Actions.
4. The workflow waits for built-in smoke checks: local
   `http://127.0.0.1:9293/healthz`, public `/healthz`, `/latest`, and
   `/en/latest`.
5. Manually smoke test one user profile and one badge URL after the workflow finishes.
6. Check Sentry for new deploy errors and latency regressions.

## Rollback

1. Open the `CI and deploy` workflow with `Run workflow`.
2. Choose `action = rollback`.
3. The workflow swaps only `latest` and `previous`; it does not roll back farther
   than one version.
4. Confirm the built-in smoke checks pass, then manually smoke test the same
   user profile and badge URL as during deploy.
5. Keep the Sentry incident open until errors and latency return to baseline.

## Restart services

Use these commands on the server:

```sh
sudo systemctl restart polish-open-source-rank.service
sudo systemctl restart polish-open-source-rank-discord-bot.service
sudo systemctl restart polish-open-source-rank-crawl-resume.service
```

Monthly and package jobs are long-running one-shot units. Do not restart them
before checking whether they are actively writing:

```sh
systemctl status polish-open-source-rank-monthly.service --no-pager
systemctl status polish-open-source-rank-packages.service --no-pager
curl -fsS -u "$INTERNAL_BASIC_AUTH_USERNAME" https://polish-open-source.pl/internal/jobs
```

Internal operations pages must require application Basic Auth. A request without
credentials should fail with the app-owned challenge:

```sh
curl -fsS -o /dev/null -w '%{http_code}\n' https://polish-open-source.pl/internal/jobs
```

Expected status: `401`.

## Stuck monthly or packages

1. Check `/internal/jobs` with the application Basic Auth credentials for the active
   section and last heartbeat.
2. Check Sentry for the matching `monthly-rankings` or `package-rankings` check-in.
3. Inspect the host alert timer with `journalctl -u polish-open-source-rank-alerts.service -n 50 --no-pager`.
4. Inspect job logs with `journalctl -u polish-open-source-rank-monthly.service -n 200 --no-pager` or the packages unit.
5. If the job is stale and no process is still doing useful work, stop the unit
   and run `bin/resume_crawls` through
   `polish-open-source-rank-crawl-resume.service`.

## Restore backup

1. Stop web, Discord bot, monthly and packages units.
2. Copy the selected SQLite backup to a temporary path.
3. Run an integrity check on the copy.
4. Replace the active public snapshot or working database only after the integrity check passes.
5. Start web first, smoke test public pages, then restart background units.
