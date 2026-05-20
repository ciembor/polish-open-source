# Refactoring Plan

This plan describes a full architectural refactor toward DDD, Clean Architecture, SOLID, and the local design rules from `AGENTS.md`. It is intentionally incremental: the production monthly job is resumable and long-running, so the refactor must preserve existing database compatibility and deploy safely in small vertical slices.

## Goals

- Make the domain language explicit: rankings, monthly snapshots, source platforms, contributors, repositories, locations, Discord access, and public publication should be visible in names and package structure.
- Move business policy out of `SQLiteStore` and `Web::App`; infrastructure should store and translate, not decide ranking/access semantics.
- Split the current broad store into role-sized ports owned by use cases and SQLite adapters that implement those ports.
- Keep Sinatra, SQLite, Discord, GitHub/GitLab/Codeberg APIs, environment variables, caching, and systemd/deploy details as outer-layer mechanisms.
- Preserve the public website, badge URLs, OAuth flows, Discord role behavior, monthly job resume behavior, and existing SQLite data during the refactor.
- Add architecture tests so the dependency direction stays correct after the cleanup.

## Non-Goals

- Do not rewrite the application in another framework.
- Do not introduce a remote service boundary, message bus, ORM, or event-sourcing layer just to look like DDD.
- Do not rename production database columns destructively in the same step as code extraction. `github_id` is a leaky persistence name today; the domain should move to `source_id` first, then persistence can be migrated later.
- Do not split small classes unless the new boundary hides real complexity. The target is deeper modules, not more files.

## Current Diagnosis

- `lib/polish_open_source_rank/infrastructure/sqlite_store.rb` is doing too much:
  - run lifecycle,
  - candidate queue,
  - monthly snapshot persistence,
  - ranking queries,
  - profile queries,
  - badge/rank policy,
  - Discord connection/invite persistence,
  - cache revision queries.
- `lib/polish_open_source_rank/web/app.rb` is also doing too much:
  - routing,
  - OAuth orchestration,
  - Discord member sync orchestration,
  - presenter/query selection,
  - HTTP cache policy,
  - URL/path helpers,
  - direct persistence calls.
- `Application::MonthlySnapshotJob` is the strongest existing use case, but it still builds persistence hashes with storage names (`github_id`, `user_github_id`, `repository_github_id`) and knows too much about source DTO shape.
- `Domain` currently contains mostly location classification. Ranking policy, access policy, badge policy, platform identity, scope, and period concepts are either implicit in SQL or spread across web/store code.
- `Web::Auth::DiscordGateway` lives under `web`, but it is an infrastructure adapter used by both web OAuth and the Discord bot.
- The read side and write side have different needs but share one store interface. That amplifies changes: adding a profile field, changing ranking logic, or changing Discord access touches unrelated methods.

## Target Architecture

Use one process and one database, but organize the code as explicit contexts with inward dependencies.

```text
lib/polish_open_source_rank/
  boot.rb
  configuration.rb
  shared/
    domain/
      clock.rb
      period.rb
      platform.rb
      source_identity.rb
      source_url.rb
    application/
      transaction.rb
      unit_of_work.rb
    infrastructure/
      sqlite/
        database.rb
        schema.rb
        migrations/
      http/
        rate_limited_json_client.rb

  contexts/
    ranking/
      domain/
        candidate.rb
        contributor.rb
        repository.rb
        repository_snapshot.rb
        contributor_snapshot.rb
        location.rb
        location_catalog.rb
        location_classifier.rb
        ranking_metric.rb
        ranking_scope.rb
        ranking_policy.rb
        snapshot_run.rb
      application/
        run_monthly_snapshot.rb
        ports/
          candidate_queue.rb
          code_host_source.rb
          snapshot_repository.rb
          snapshot_run_repository.rb
          ranking_retention.rb
          source_request_log.rb
      infrastructure/
        code_hosts/
          github_source.rb
          gitlab_source.rb
          codeberg_source.rb
          github_client.rb
          gitlab_client.rb
          codeberg_client.rb
        sqlite/
          sqlite_candidate_queue.rb
          sqlite_snapshot_repository.rb
          sqlite_snapshot_run_repository.rb
          sqlite_ranking_retention.rb
          sqlite_source_request_log.rb

    publication/
      domain/
        badge.rb
        badge_policy.rb
        edition.rb
        public_cache_revision.rb
        rank.rb
      application/
        show_rankings.rb
        show_ranking_detail.rb
        show_user_profile.rb
        show_repository_profile.rb
        list_editions.rb
        render_badge.rb
        ports/
          ranking_read_model.rb
          profile_read_model.rb
          edition_read_model.rb
          cache_revision_read_model.rb
      infrastructure/
        sqlite/
          sqlite_ranking_read_model.rb
          sqlite_profile_read_model.rb
          sqlite_edition_read_model.rb
          sqlite_cache_revision_read_model.rb

    community/
      domain/
        discord_access.rb
        discord_role_key.rb
        discord_role_policy.rb
        invitation.rb
        linked_discord_account.rb
      application/
        connect_discord_account.rb
        sync_invite_join.rb
        detect_used_invite.rb
        ports/
          discord_member_gateway.rb
          discord_connection_repository.rb
          discord_invite_repository.rb
          contributor_access_read_model.rb
      infrastructure/
        discord/
          discord_api_gateway.rb
          discord_oauth_client.rb
          discord_role_map.rb
          discord_welcome_message.rb
          discord_invite_bot.rb
        sqlite/
          sqlite_discord_connection_repository.rb
          sqlite_discord_invite_repository.rb
          sqlite_contributor_access_read_model.rb

    operations/
      application/
        show_job_progress.rb
      infrastructure/
        sqlite_job_progress_read_model.rb

  interfaces/
    web/
      app.rb
      routes/
        public_routes.rb
        auth_routes.rb
        badge_routes.rb
        internal_routes.rb
      controllers/
        ranking_controller.rb
        profile_controller.rb
        auth_controller.rb
        discord_controller.rb
        badge_controller.rb
        job_monitor_controller.rb
      presenters/
        ranking_presenter.rb
        profile_presenter.rb
        job_progress_presenter.rb
      http_cache.rb
      localization/
      views/
      public/
    cli/
      monthly_rankings.rb
      discord_bot.rb
    composition/
      container.rb
      ranking_job_factory.rb
      web_factory.rb
      discord_bot_factory.rb
```

This tree is a target shape, not a first patch. Keep existing `app/views` and `app/public` until the web interface layer is ready to own them without noisy churn.

## Dependency Rules

- `shared/domain` and every `contexts/*/domain` namespace must not depend on Sinatra, SQLite, HTTP clients, Discord, ENV, file paths, or framework response objects.
- `contexts/*/application` may depend on its own domain objects and its own port interfaces. It must not instantiate infrastructure.
- `contexts/*/infrastructure` may depend inward on the context domain/application port contracts and outward on SQLite, HTTP, Discord, and platform SDKs.
- `interfaces/web` may depend on application use cases and presenters. It must not contain ranking, badge, or Discord access policy.
- `interfaces/cli` and `interfaces/composition` are composition roots. They may wire concrete adapters.
- No context may reach into another context's infrastructure. Cross-context collaboration must go through an application use case, read model, or explicit domain concept in `shared`.

## Ubiquitous Language and Naming

Use these terms consistently:

- `Platform`: `github`, `gitlab`, `codeberg`.
- `SourceIdentity`: pair of `platform` and `source_id`.
- `Contributor`: a public user/profile from a source platform.
- `Project`: a repository/package being ranked. Prefer `Project` in domain if the product language moves beyond Git repositories; otherwise use `Repository` consistently.
- `MonthlySnapshot`: collected contributor/project state for one calendar month.
- `Candidate`: a possible contributor discovered from source search.
- `RankingScope`: Poland or a city.
- `RankingMetric`: total stars, monthly stars delta, public activity.
- `Rank`: calculated position with tie-breaking semantics.
- `DiscordAccess`: channel and role access derived from ranks.
- `Publication`: public read side: rankings, profiles, editions, badges.

Do not expose persistence names such as `github_id` in domain/application APIs. During migration, SQLite adapters can still map `source_id` to existing columns.

## Refactor Phases

### Phase 0: Safety Rails Before Movement

- [x] Add `spec/architecture/dependency_rules_spec.rb` with simple file/constant scans:
   - domain files must not reference `Infrastructure::`, `Web::`, `Sinatra`, `SQLite3`, `ENV`, `Net::HTTP`, or `Discordrb`.
   - application files must not reference `SQLite3`, `Sinatra`, `Net::HTTP`, or `Discordrb`.
   - infrastructure files must not be required from domain.
- [x] Add golden coverage for critical behavior before extraction:
   - monthly job resume after failed/interrupted run,
   - ranking order/tie-breakers,
   - pruning keeps all public top 100 records,
   - Discord role decisions for top 10/top 100/city,
   - public cache headers and badge output.
- [x] Keep `bin/quality` green after every phase.

### Phase 1: Shared Kernel Value Objects

Introduce small but meaningful value objects:

- [x] `Shared::Domain::Period` from current `Application::MonthPeriod`.
- [x] `Shared::Domain::Platform`.
- [x] `Shared::Domain::SourceIdentity`.
- [x] `Ranking::Domain::RankingScope`.
- [x] `Ranking::Domain::RankingMetric`.

Rules:

- [x] These objects validate invariants once and remove repeated string/date parsing from callers.
- [x] Keep backward-compatible constructors from existing strings so controllers and tests can migrate gradually.
- [x] Do not change SQLite schema yet.

### Phase 2: Extract Ranking Domain From SQL/Web

Move pure policy out of `SQLiteStore`:

- [x] `Ranking::Domain::LocationCatalog` and `LocationClassifier` from current `Domain`.
- [ ] `Ranking::Domain::RankingPolicy` for metric definitions, limits, tie-breakers, and trending filter.
- [x] `Publication::Domain::BadgePolicy` for user/repository badge status and ordinal label.
- [x] `Community::Domain::DiscordRolePolicy` for top 10/top 100/city role keys.

Expected deletions from `SQLiteStore`:

- [x] `discord_access_role_keys`,
- [x] `discord_badge_role_key`,
- [x] `rank_place`,
- [x] `ordinal_suffix`,
- [ ] scope/metric string knowledge except SQL translation.

### Phase 3: Split `SQLiteStore` by Owned Port

Create one shared SQLite connection wrapper:

- [x] `Shared::Infrastructure::SQLite::Database`
  - owns path, connection, PRAGMA, busy timeout, transactions, row symbolization;
  - exposes `execute`, `fetch_all`, `fetch_value`, `transaction`;
  - does not expose domain decisions.

Then extract adapters behind use-case-owned ports:

- Ranking write side:
  - `SQLiteSnapshotRunRepository`
  - [x] `SQLiteCandidateQueue`
  - `SQLiteSnapshotRepository`
  - `SQLiteRankingRetention`
  - `SQLiteSourceRequestLog`
- Publication read side:
  - [x] `SQLiteRankingReadModel`
  - [x] `SQLiteProfileReadModel`
  - [x] `SQLiteEditionReadModel`
  - [x] `SQLiteCacheRevisionReadModel`
- Community:
  - [x] `SQLiteDiscordConnectionRepository`
  - [x] `SQLiteDiscordInviteRepository`
  - [x] `SQLiteContributorAccessReadModel`
- Operations:
  - [x] `SQLiteJobProgressReadModel`

Keep a temporary `Infrastructure::SQLiteStore` facade only as an anti-corruption layer for tests and old callers. Delete it after callers move to the new ports.

### Phase 4: Reshape Monthly Snapshot as a Use Case

Rename and move:

- [x] `Application::MonthlySnapshotJob` -> `Ranking::Application::RunMonthlySnapshot`.
- [ ] `Application::MonthlySnapshotCommand` -> `Interfaces::CLI::MonthlyRankingsCommand` or `Ranking::Application::RunMonthlySnapshotCommand` if it remains framework-free.
- [ ] `Infrastructure::MonthlySnapshotComposition` -> `Interfaces::Composition::RankingJobFactory`.

Introduce source DTOs in the ranking context:

- [ ] `Ranking::Domain::SourceCandidate`
- [ ] `Ranking::Domain::SourceContributor`
- [ ] `Ranking::Domain::SourceRepository`

The source gateways should return these DTOs, not generic hashes. The use case should stop constructing persistence hashes. It should pass domain snapshots to `SnapshotRepository`.

Target use-case dependencies:

```ruby
RunMonthlySnapshot.new(
  runs:,
  candidates:,
  snapshots:,
  retention:,
  sources:,
  classifier:,
  clock:,
  logger:
)
```

The use case remains allowed to coordinate discovery, candidate processing, retries, and completion. Persistence details and source HTTP details stay behind ports.

### Phase 5: Separate Publication Read Models From Web

Create application queries:

- `Publication::Application::ShowRankings`
- `Publication::Application::ShowRankingDetail`
- `Publication::Application::ShowUserProfile`
- `Publication::Application::ShowRepositoryProfile`
- `Publication::Application::ListEditions`
- `Publication::Application::RenderBadge`

Each returns plain response models, for example:

- `RankingsPage`
- `ProfilePage`
- `RepositoryPage`
- `EditionIndex`
- `BadgeView`

Move the current ranking/profile SQL into publication read model adapters. Keep SQL optimized and close to SQLite, but return explicit models rather than raw row hashes.

After this phase, web controllers should not call methods like `store.user_rankings`, `store.user_profile`, or `store.discord_access` directly.

### Phase 6: Split Sinatra App Into Thin Routes and Controllers

Keep Sinatra, but make it a delivery adapter:

- `Interfaces::Web::App` wires middleware, sessions, helpers, and route modules.
- Route files only parse path/query/session and call controllers.
- Controllers call application use cases and return render instructions.
- Presenters map application response models to ERB-friendly hashes.
- `Interfaces::Web::HttpCache` owns ETag/cache header decisions.

Suggested route grouping:

- `PublicRoutes`: rankings, editions, profiles, about.
- `AuthRoutes`: GitHub OAuth, logout, unranked.
- `DiscordRoutes`: Discord OAuth callback.
- `BadgeRoutes`: SVG badge endpoints.
- `InternalRoutes`: health and job monitor.

This should shrink the main app class from roughly 700 lines to wiring plus route registration.

### Phase 7: Move Community/Discord Out of Web

Move these classes out of `web/auth`:

- `DiscordGateway` -> `Community::Infrastructure::Discord::DiscordApiGateway`
- `DiscordRoleMap` -> `Community::Infrastructure::Discord::DiscordRoleMap`
- `DiscordWelcomeMessage` -> `Community::Infrastructure::Discord::DiscordWelcomeMessage`
- `DiscordInviteBot` -> `Community::Infrastructure::Discord::DiscordInviteBot`

Keep OAuth clients under the web interface or a dedicated identity adapter:

- `GitHubOAuthClient` belongs to `Interfaces::Web::Auth` because it exists for browser login.
- `DiscordOAuthClient` can stay in `Interfaces::Web::Auth` if only the web flow uses it.

Create use cases:

- `Community::Application::ConnectDiscordAccount`
- `Community::Application::SyncInviteJoin`

The web Discord callback should call `ConnectDiscordAccount`; the bot should call `SyncInviteJoin`. Both should share `DiscordRolePolicy`.

### Phase 8: Rename Persistence Concepts Without Breaking Production

Domain/application rename:

- `github_id` -> `source_id`
- `user_github_id` -> `contributor_source_id`
- `repository_github_id` -> `repository_source_id`

SQLite compatibility strategy:

1. First update Ruby domain models and ports to speak `source_id`.
2. Keep SQLite adapters mapping to old columns.
3. Add schema migration with new columns only after adapters are stable:
   - add nullable new columns,
   - backfill from old columns,
   - write both names for one deploy,
   - read new names,
   - later remove old names only if we accept a destructive migration.

Given SQLite and production job safety, stopping after step 3 with compatibility columns is acceptable. The most important cleanup is domain language, not physical column renaming.

### Phase 9: Composition Root and Boot Cleanup

Replace `lib/polish_open_source_rank.rb` as an all-requires file with explicit boot files:

- `boot/domain.rb`
- `boot/ranking_job.rb`
- `boot/web.rb`
- `boot/discord_bot.rb`
- `boot/test.rb`

CLI and web entrypoints should require only what they need:

- `bin/monthly_rankings` -> `interfaces/cli/monthly_rankings`
- `bin/discord_bot` -> `interfaces/cli/discord_bot`
- `config.ru` -> `interfaces/web/app`

Composition root should own:

- configuration loading,
- concrete SQLite adapters,
- concrete source clients,
- Discord clients,
- clocks,
- loggers.

### Phase 10: Tests After the Refactor

Mirror production structure:

```text
spec/
  architecture/
  shared/
  contexts/
    ranking/
      domain/
      application/
      infrastructure/
    publication/
    community/
    operations/
  interfaces/
    web/
    cli/
```

Testing rules:

- Domain specs use plain objects only.
- Application specs use fake ports.
- SQLite adapter specs verify SQL, schema compatibility, indexes, migrations, and query models.
- Web specs verify routing/session/cache/rendering, not ranking policy.
- Keep end-to-end Rack specs for the most important paths:
  - latest ranking page,
  - profile + Discord panel,
  - GitHub OAuth login,
  - Discord callback,
  - badges,
  - internal job monitor.

## Suggested Commit Sequence

1. `Add architecture dependency specs`
2. `Introduce shared platform and source identity values`
3. `Move period and location into ranking domain`
4. `Extract ranking and badge policies`
5. `Introduce SQLite database wrapper`
6. `Extract ranking write-side SQLite adapters`
7. `Move monthly snapshot use case to ranking context`
8. `Extract publication read models`
9. `Move public web pages to publication use cases`
10. `Extract HTTP cache helper and route modules`
11. `Extract community Discord policies and use cases`
12. `Move Discord infrastructure out of web`
13. `Replace SQLiteStore facade callers`
14. `Delete SQLiteStore facade`
15. `Reorganize boot/composition entrypoints`
16. `Rename specs and remove obsolete compatibility helpers`

Keep every commit deployable. If a step cannot be completed without touching too many callers, introduce a temporary facade and delete it in the next commit.

## Production Safety Plan

- Do not run destructive migrations while the monthly job is active.
- Maintain resume semantics for `sync_runs`, `candidate_users`, and monthly stats during all phases.
- Prefer additive schema changes first.
- Keep `busy_timeout`, indexes, and job progress queries covered by tests.
- Before deploys that touch snapshot write paths:
  - run full `bin/quality`,
  - test a resume scenario locally,
  - verify `/internal/jobs` after deploy,
  - do not manually restart the monthly job unless the change explicitly requires it.

## Architecture Fitness Checks

Add these checks as code, not just documentation:

- Domain does not reference infrastructure or web constants.
- Application does not instantiate infrastructure classes.
- Web controllers do not call SQLite adapters directly after Phase 5.
- Every context has at least one application spec with fake ports for non-trivial use cases.
- No new class named `*Service` unless the name is replaced by a use-case verb or a domain concept.
- No new raw hash response from a use case when a named response model would reduce caller knowledge.

## Final Acceptance Criteria

- Main Sinatra app is thin route wiring, not a 700-line controller.
- No broad `SQLiteStore` remains; SQLite adapters are grouped by role and implement use-case-owned ports.
- Ranking, badge, Discord access, and location policies are plain domain/application code with fast tests.
- Source platform adapters return domain DTOs and hide API pagination/rate-limit quirks.
- Public pages are backed by publication read models, not write-side repositories.
- Discord bot and Discord OAuth share community use cases and policies.
- Domain/application layers can be tested without SQLite, Sinatra, network, Discord, or environment variables.
- Directory structure reveals the product capabilities: ranking, publication, community, operations.
- The public behavior and production database compatibility remain intact throughout the refactor.
