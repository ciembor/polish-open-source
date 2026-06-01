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

## Composition Model

`PolishOpenSourceRank::Web::App` owns request flow only: locale redirects,
session-cookie deferral, cache helpers, route helpers, and the current request's
composition instance. Boot-time concerns live in `PolishOpenSourceRank::Web::Boot`
so middleware order, session cookie settings, helper registration, route
registration, and static view services stay out of request handlers.

The web composition root is still an outer-layer detail. It exposes context
collaborators instead of individual use-case delegators:

- `publication` for public rankings, profiles, badges, period resolution, and
  public cache revision decisions.
- `packages` for package index, ecosystem, and ranking-detail use cases.
- `languages` for language index and language ranking use cases.
- `community` for OAuth clients, Discord role sync, Discord panel state, and
  contributor access.
- `operations` for internal job progress.

Controllers should call those context collaborators directly, for example
`publication.show_rankings` or `packages.show_package_index`. New web use cases
should be added to the narrow owning context instead of adding pass-through
delegators to `Web::App`.

HTML cache revisions are calculated by `PolishOpenSourceRank::Web::HtmlRevision`.
It watches all ERB views, public CSS, public JavaScript, and the selected locale
file, so adding a new view automatically invalidates public HTML ETags without
updating a manual manifest.
