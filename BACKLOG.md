# Polish Open Source Rank Backlog

This backlog is ordered by impact on the project as a public engineering
showcase. Security and production credibility come first, then deploy/runtime
reliability, public product polish, architecture, data quality, and long-term
maintainability.

Rules for executing this backlog:

- Do not check off a task until implementation, tests, docs, and pre-commit pass.
- Production-facing tasks require a documented verification path and rollback
  path before deployment.
- Prefer small commits per task or per tightly related task group.
- Keep docs as the source of truth and skills as thin operational workflows.

## Milestone 1: Production Security Hardening

Goal: remove public security footguns before spending more time on polish.

- [ ] Protect `/internal/jobs` with production-grade access control.
- [ ] Add regression tests proving anonymous users cannot access internal
      operational pages in production mode.
- [ ] Replace direct trust in arbitrary `X-Forwarded-For` with a trusted proxy
      client IP policy.
- [ ] Add tests for spoofed forwarded headers and rate-limit key selection.
- [ ] Decide whether rate limiter state should remain in-process or move to a
      shared store for the current production shape.
- [ ] Add global security headers: `Content-Security-Policy`,
      `X-Content-Type-Options`, `Referrer-Policy`, `Permissions-Policy`, and
      `frame-ancestors`.
- [ ] Add regression specs for security headers on public, auth, badge, and
      internal responses.
- [ ] Add `rel="noopener noreferrer"` to every external
      `target="_blank"` link, including generated badge HTML.
- [ ] Add focused auth security regression specs for logout CSRF, OAuth state
      replay, and failed OAuth callback behavior.

## Milestone 2: CI and Supply Chain Security

Goal: make the public repository credible under security review.

- [ ] Replace deploy-time `ssh-keyscan` trust-on-first-use with pinned host key
      verification from GitHub Actions secrets.
- [ ] Pin GitHub Actions permissions to the least required scope.
- [ ] Pin third-party GitHub Actions by SHA or document why version tags are
      acceptable for this repository.
- [ ] Add Dependabot configuration for Ruby gems and GitHub Actions.
- [ ] Add `bundler-audit` or equivalent dependency vulnerability scanning to CI.
- [ ] Add CodeQL, Semgrep, Brakeman, or an equivalent Ruby/web security scan to
      CI.
- [ ] Split CI quality from deploy so deploy depends on a named, inspectable
      quality job.
- [ ] Consider a GitHub Environment for production deploys and document whether
      manual approval is required.

## Milestone 3: Runtime and Container Hardening

Goal: ensure production runtime matches the tested runtime and follows container
basics.

- [ ] Align Docker Ruby version with the project runtime declared in CI and the
      lockfile.
- [ ] Pin the base image version or digest and document the update policy.
- [ ] Run the production container as a non-root user.
- [ ] Ensure writable runtime directories (`db`, `log`, `tmp`) work correctly
      under the non-root user.
- [ ] Add a container build smoke test to CI.
- [ ] Add a production-like container health smoke test for `/healthz`.
- [ ] Review systemd unit hardening options for web, bot, monthly, packages,
      crawl, alerts, and monitor services.
- [ ] Document the exact runtime parity expectations in `docs/deployment.md`.

## Milestone 4: Public Product Polish

Goal: make the website feel like a strong public showcase, not only a working
ranking table.

- [ ] Review the first viewport on desktop and mobile for clear value,
      credibility, and immediate navigation to people, organizations, packages,
      languages, and editions.
- [ ] Improve the About page so it explains the ranking methodology, data
      freshness, limitations, and why the project exists.
- [ ] Make metric explanations visible near rankings without cluttering the
      tables.
- [ ] Add clearer empty, stale, and partially available data states.
- [ ] Improve profile pages as shareable portfolio surfaces for ranked users,
      repositories, organizations, and packages.
- [ ] Add social preview checks for key public URLs.
- [ ] Add visual or snapshot coverage for the most important public pages.
- [ ] Audit mobile layout for navigation, tables, profile pages, packages, and
      languages.
- [ ] Decide whether README should stay as a generated ranking showcase or become
      a shorter project landing document with links to the live site.

## Milestone 5: Architecture Simplification

Goal: reduce central web complexity while preserving the current Clean
Architecture boundaries.

- [ ] Extract web boot concerns from `Web::App`: middleware, sessions,
      observability, static config, and route registration.
- [ ] Extract cache revision calculation from `Web::App`.
- [ ] Replace the manual `HTML_REVISION_FILES` list with a directory or manifest
      mechanism that cannot silently miss new views.
- [ ] Split `Web::Composition` by bounded context or use-case cluster while
      keeping construction in the outer layer.
- [ ] Reduce `Web::App` delegators by routing through narrower context-specific
      collaborators.
- [ ] Keep architecture specs updated so new boundaries are enforced, not only
      documented.
- [ ] Add tests around composition wiring before and after extraction.
- [ ] Document the intended web composition model in `docs/web-app.md` or
      `docs/development.md`.

## Milestone 6: Stronger Domain Contracts

Goal: remove stringly typed and hash-shaped contracts where mistakes would be
expensive.

- [ ] Introduce explicit value objects or request models for repository full
      names where platform owner/name parsing matters.
- [ ] Strengthen platform, period, ecosystem, login, and repository identity
      boundaries at use-case edges.
- [ ] Replace mutable domain structs where mutation is not part of the domain
      concept.
- [ ] Review public read model APIs for plain but typed request/response models
      instead of loose hashes where it reduces caller knowledge.
- [ ] Whitelist every SQL identifier interpolation through a single explicit
      metric/order expression API.
- [ ] Add regression specs proving unsupported metric/order inputs cannot reach
      SQL fragments.
- [ ] Keep read-model SQL expressive, but hide volatile SQL fragments behind
      semantic methods.

## Milestone 7: Data Quality and Ranking Trust

Goal: make rankings defensible when users question why something is included,
missing, or ordered.

- [ ] Add a public methodology section that explains source coverage, platform
      limitations, GitHub historical stars, and non-GitHub fallbacks.
- [ ] Add internal data-quality reports for candidate coverage, rejected
      locations, missing repositories, missing organizations, and package link
      confidence.
- [ ] Add anomaly checks for extreme monthly star deltas, missing profile fields,
      duplicate identities, and unexpectedly empty city rankings.
- [ ] Add a manual review path for false positives and false negatives in Polish
      location classification.
- [ ] Preserve enough source evidence to explain why a user or organization is
      classified as Polish without exposing private data.
- [ ] Add tests for package source repository matching edge cases across major
      ecosystems.
- [ ] Add a post-publication checklist that confirms current public data is
      complete before promoting `latest`.
- [ ] Decide how unsupported platform metrics should be represented in UI:
      hidden, zero, unavailable, or explicitly explained.

## Milestone 8: Performance and Scalability Readiness

Goal: keep the single-host SQLite architecture excellent until evidence says it
needs to change.

- [ ] Run and archive a fresh production load profile for the current public
      site.
- [ ] Run and archive public SQLite query plans against a production-sized
      database.
- [ ] Add indexes only where production-sized plans and latency prove they are
      needed.
- [ ] Add CI or scheduled checks for public read-path performance regressions
      where practical.
- [ ] Verify cache behavior for PL and EN public pages, profiles, badges,
      packages, languages, and editions.
- [ ] Revisit the separate read-only public snapshot database path and decide
      whether production should use it by default.
- [ ] Document explicit thresholds for moving gzip, caching, or rate limiting out
      of the Rack process.
- [ ] Keep spike response docs aligned with the actual nginx/CDN configuration.

## Milestone 9: Operations Excellence

Goal: make production operation boring, observable, and easy to recover.

- [ ] Test restore from the documented SQLite backup path on a disposable copy.
- [ ] Add a scheduled backup restore drill or at least a documented quarterly
      manual procedure.
- [ ] Verify Sentry alerts for stalled monthly jobs, stalled package jobs, 5xx
      spikes, latency spikes, and SQLite retry spikes.
- [ ] Ensure every production alert has a corresponding runbook action.
- [ ] Add smoke checks for Discord bot health and invite workflow health.
- [ ] Add operational checks for monthly and package job progress after deploys.
- [ ] Review production systemd timers and services for stale, obsolete, or
      overlapping operational paths.
- [ ] Keep `skills/production-ops` synchronized with production docs whenever
      operations change.

## Milestone 10: Test and Quality Gate Tightening

Goal: keep the project pleasant to change as it grows.

- [ ] Remove duplicated `RSpec.configure` setup from `spec/spec_helper.rb`.
- [ ] Re-enable or consciously replace `RSpec/VerifiedDoubles`.
- [ ] Tighten RuboCop limits gradually where the current limits hide real design
      pressure.
- [ ] Align `.rubocop.yml` `TargetRubyVersion` with the supported runtime.
- [ ] Add mutation testing to the documented quality workflow for high-risk
      changed domain/application code.
- [ ] Add security regression specs to the normal quality gate.
- [ ] Add targeted architecture specs for any new web composition boundaries.
- [ ] Keep Reek clean and avoid suppressions unless the design rationale is
      documented.

## Milestone 11: Documentation and Public Credibility

Goal: make the repository easy to evaluate by recruiters, engineers, and future
contributors.

- [ ] Add a concise architecture decision record for the single-host SQLite
      architecture and its limits.
- [ ] Add a public-facing methodology document linked from the site and README.
- [ ] Add a security posture document covering internal endpoints, deploy,
      secrets, OAuth, rate limiting, and backups.
- [ ] Add a data privacy note explaining what public data is collected and why.
- [ ] Keep `docs/README.md` as the canonical documentation index.
- [ ] Keep repo-local skills thin and linked back to docs.
- [ ] Add a contributor-friendly "how to safely change rankings" guide.
- [ ] Add release or publication notes for major ranking methodology changes.

## Milestone 12: Community and Showcase Features

Goal: turn the project from a ranking site into a credible community asset.

- [ ] Improve badge onboarding so logged-in users can quickly choose and copy the
      right badge.
- [ ] Add clearer Discord invite eligibility explanations and failure states.
- [ ] Add share links for profile pages, repository pages, package pages, and
      language rankings.
- [ ] Add a lightweight feedback/report flow for incorrect location or ownership
      data.
- [ ] Add pages or sections highlighting monthly changes: new entrants, biggest
      movers, and notable packages.
- [ ] Add stable canonical URLs for historical editions and methodology snapshots.
- [ ] Decide whether to expose a small public JSON endpoint or downloadable data
      snapshot for community reuse.
