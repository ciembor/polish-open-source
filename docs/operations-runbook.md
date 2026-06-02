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

## Production session secret

`SESSION_SECRET` in `/home/ciembor/polish-open-source-rank/.env.local` must be
at least 64 characters. Generate a value with:

```sh
ruby -rsecurerandom -e 'puts SecureRandom.hex(32)'
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
curl -fsS -u ciembor https://polish-open-source.pl/internal/jobs
```

Internal operations pages must require nginx Basic Auth. A request without
credentials should fail before reaching the Rack app:

```sh
curl -fsS -o /dev/null -w '%{http_code}\n' https://polish-open-source.pl/internal/jobs
```

Expected status: `401`.

## Stuck monthly or packages

1. Check `/internal/jobs` with the nginx Basic Auth credentials for the active
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
