# Web App

## Local Server

```sh
bin/server
```

## Public Routes

- `/` for the Poland ranking.
- `/locations/krakow`, `/locations/wroclaw`, `/locations/warszawa`,
  `/locations/gdansk`, `/locations/poznan`, `/locations/szczecin`,
  `/locations/lodz` for city rankings.
- `/packages` for package ecosystems.
- `/latest/packages/npm`, `/latest/packages/npm/top`,
  `/latest/packages/npm/downloads`, `/latest/packages/npm/dependents`.
- `/healthz`.

The HTML uses semantic sections, tables, canonical URLs, meta descriptions, and
JSON-LD dataset metadata.

## Cache and Edge Expectations

Public pages are intentionally cacheable by URL. Polish pages use the default
unprefixed routes, English pages use `/en/...`, and both variants expose
self-canonical and `hreflang` links. The `locale` cookie is only a redirect
preference and must not become the shared cache key for indexed pages.

Recommended edge rules:

- Cache anonymous `GET` and `HEAD` HTML for public ranking, profile, language,
  package, and badge routes.
- Bypass shared cache whenever the request carries the signed session cookie
  `polish_open_source_rank.session`.
- Vary cached public HTML by path and query string, not by arbitrary cookies.
- Keep `/auth/*`, `/logout`, `/internal/*`, and responses with
  `Cache-Control: private` or `no-store` out of shared cache.
- Rate-limit `/auth/*`, `/badges/*`, `/internal/*`, and ranking-detail bursts
  before requests reach the Rack app.
- Do not rate-limit normal search crawler access to indexed Polish and English
  pages. If crawler-specific limits are needed, verify them at the edge with
  reverse DNS instead of trusting `User-Agent`.

## Internal Operations Access

`/internal/*` routes are operational pages and must be protected at nginx before
requests reach the Rack app. The app still marks those responses as `no-store`
and `noindex`, but indexing headers are not access control.

The Rack rate limiter remains in-process for the current production shape: one
web container behind nginx plus nginx edge rate limits. It only trusts
`X-Real-IP` or `X-Forwarded-For` when `REMOTE_ADDR` belongs to a trusted local or
private proxy address.
