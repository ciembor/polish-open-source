# Refactoring Plan: migrate persistence to Sequel

This plan replaces the current hand-written `sqlite3` database wrapper with Sequel while preserving the existing Clean Architecture boundaries. Sequel is an infrastructure detail: domain and application code must keep using role-sized ports and plain request/response objects.

## Goals

- Use Sequel for SQLite connection management, transactions, datasets, inserts, updates, and safe SQL composition.
- Keep the existing SQLite database file, schema, public URLs, monthly job resume behavior, Discord flows, badges, and ranking output compatible during the migration.
- Reduce persistence boilerplate without pushing Sequel objects into domain, application use cases, web controllers, or views.
- Preserve the current context structure: Ranking, Publication, Community, Operations, Shared, Web, CLI, Composition.
- Keep complex ranking/read-model SQL where it is clearer than a fluent dataset chain, but execute and bind it through Sequel.
- End with no production dependency on `SQLite3::Database` outside transitional compatibility tests or removed legacy code.

## Non-Goals

- Do not migrate to Active Record.
- Do not redesign the database schema as part of the Sequel migration.
- Do not rename persistence columns such as `github_id` in the same pass.
- Do not introduce Sequel models as domain entities.
- Do not add repositories that simply wrap one Sequel call without hiding persistence complexity.
- Do not replace stable SQL queries with less readable dataset code just to avoid SQL strings.

## Current Persistence Shape

- `Shared::Infrastructure::SQLite::Database` wraps `SQLite3::Database` and exposes `execute`, `execute_batch`, `fetch_all`, `fetch_value`, `transaction`, and `table_info`.
- Most context adapters depend on that wrapper, not directly on `SQLite3::Database`.
- `Infrastructure::SQLiteStore` still exists as a legacy facade and compatibility surface.
- `PlatformSchemaMigration` and `SQLiteSchema` own schema bootstrapping and legacy GitHub-only migration.
- Ranking read models and retention logic contain the most complex SQL and should be migrated carefully.
- Specs still create raw `SQLite3::Database` connections in several integration-style helpers.

## Target Shape

```text
lib/polish_open_source_rank/
  shared/
    infrastructure/
      sqlite/
        database.rb              # Sequel-backed database gateway
        sql.rb                   # optional helper for raw SQL fragments if needed
  infrastructure/
    sqlite_schema.rb             # unchanged SQL schema source, initially
    platform_schema_migration.rb # Sequel-backed migration runner
    sqlite_store.rb              # deleted or reduced to test-only compatibility before removal

  contexts/*/infrastructure/sqlite/
    # adapters keep their public port contracts
    # internals use Sequel datasets or Sequel-bound raw SQL
```

Sequel belongs in infrastructure adapters and shared SQLite infrastructure only. It must not leak into use cases, controllers, domain objects, response models, or view helpers.

## Migration Strategy

### 1. Add Sequel and introduce the database gateway

- [ ] Add `gem 'sequel', '~> 5.x'` to `Gemfile`.
- [ ] Keep `sqlite3` as the database driver; Sequel uses it underneath.
- [ ] Replace `Shared::Infrastructure::SQLite::Database` internals with a Sequel connection while preserving its current public API:
  - `open(path)`
  - `execute(sql, params = [])`
  - `execute_batch(sql)`
  - `fetch_all(sql, params = [])`
  - `fetch_value(sql, params = [])`
  - `transaction`
  - `table_info(table_name)`
- [ ] Preserve connection settings:
  - foreign keys enabled,
  - busy timeout,
  - results returned as symbol-keyed hashes for adapter callers.
- [ ] Add focused tests proving the wrapper still satisfies the existing database contract.
- [ ] Do not touch context adapters in this step except where the wrapper contract requires a tiny compatibility fix.

### 2. Move schema bootstrapping and migrations onto Sequel

- [x] Update `PlatformSchemaMigration` to depend on the Sequel-backed database gateway, not raw `SQLite3::Database`.
- [x] Keep `SQLiteSchema.sql` as the initial schema source.
- [x] Use Sequel transactions for migration steps that mutate schema/data.
- [x] Preserve current `PRAGMA user_version` behavior.
- [x] Add regression tests for:
  - fresh database creation,
  - legacy GitHub-only migration,
  - idempotent migration when schema is current.

### 3. Convert simple write repositories first

Start with adapters where Sequel datasets clearly reduce boilerplate and query risk.

- [x] Convert `SQLiteDiscordConnectionRepository`.
- [x] Convert `SQLiteDiscordInviteRepository`.
- [x] Convert `SQLiteSourceRequestLog`.
- [x] Convert candidate status update paths in `SQLiteCandidateQueue` where they are simple inserts/updates.
- [ ] Keep method contracts unchanged.
- [ ] Add or preserve tests around upserts, timestamps, and one-active-invite behavior.

### 4. Convert ranking snapshot write side

- [x] Convert `SQLiteSnapshotRepository` inserts/upserts to Sequel datasets.
- [x] Convert `SQLiteSnapshotRunRepository` lifecycle updates to Sequel datasets.
- [ ] Convert `MonthlySnapshotStore` only where it owns persistence orchestration; do not turn it into a pass-through Sequel wrapper.
- [ ] Keep storage-name mapping hidden in the adapter:
  - domain/application says `source_id`,
  - persistence may still write legacy `github_id` columns.
- [ ] Preserve monthly job resume behavior with integration tests.

### 5. Convert read models selectively

Read models may keep raw SQL when that is the deeper interface. The migration target is safer execution and less repeated low-level handling, not SQL elimination.

- [x] Convert simple read models to Sequel datasets:
  - `SQLiteCacheRevisionReadModel`,
  - simple methods in `SQLiteContributorAccessReadModel`,
  - simple edition-year queries in `SQLiteEditionReadModel`.
- [ ] Keep complex ranking/profile SQL as raw SQL where it is more readable:
  - ranking window/tie-break queries,
  - profile badge/history queries,
  - job progress aggregation queries.
- [x] Execute raw SQL through Sequel with bound parameters.
- [ ] Keep all public response shapes identical.

### 6. Convert ranking retention and dynamic SQL safely

- [x] Replace `SQLite3::Database.quote` usage in `SQLiteRankingRetention`.
- [ ] Prefer Sequel dataset construction for dynamic `IN` values.
- [x] If raw SQL remains, centralize quoting/binding in one infrastructure helper.
- [x] Add tests that prove city scope, metric columns, and retention limits cannot produce malformed SQL.

### 7. Convert operations job progress

- [x] Replace `Infrastructure::SQLiteJobProgress` internals with Sequel.
- [x] Keep `Contexts::Operations::Infrastructure::SQLite::SQLiteJobProgressReadModel` as the operations-facing adapter.
- [x] Preserve current progress calculations:
  - running vs finished duration,
  - per-platform progress,
  - API request counts,
  - empty snapshot when no run exists.

### 8. Remove legacy SQLite facade pressure

- [ ] Decide whether `Infrastructure::SQLiteStore` is still useful as a compatibility facade.
- [ ] If no production code needs it, delete it and migrate remaining specs to context adapters.
- [ ] If a short-lived facade remains, make it delegate to Sequel-backed adapters only.
- [x] Add an architecture rule forbidding new production references to:
  - `SQLite3::Database`,
  - `get_first_value`,
  - direct `execute_batch` outside schema/migration/database gateway,
  - `Infrastructure::SQLiteStore` outside its own file while it exists.

### 9. Update tests and fixtures

- [x] Replace raw `SQLite3::Database.new` in specs with `Shared::Infrastructure::SQLite::Database.open`.
- [ ] Keep a small number of low-level tests around the database gateway itself.
- [ ] Avoid making tests depend on Sequel internals unless testing the gateway.
- [ ] Preserve full integration coverage for:
  - monthly snapshot run,
  - web rendering,
  - profile pages,
  - badges,
  - Discord invite/account flows,
  - schema migration.

### 10. Final cleanup

- [ ] Remove direct `sqlite3` requires from production code where Sequel owns the connection.
- [ ] Keep `sqlite3` in `Gemfile` only as Sequel's SQLite adapter dependency.
- [ ] Remove unused helper methods from the database gateway after all adapters migrate.
- [ ] Rename files/classes only when it reduces cognitive load; do not churn namespaces for cosmetic reasons.
- [ ] Run and commit only after the normal pre-commit hook passes:
  - `bundle exec rubocop --cache-root tmp/rubocop_cache`
  - `bundle exec reek`
  - `bundle exec rspec`

## Design Rules

- Sequel datasets are infrastructure objects. Do not return them from adapters.
- Use Sequel to hide persistence mechanics from callers, not to expose new query-building responsibilities.
- Keep SQL close to the adapter that owns the table knowledge.
- Prefer one clear adapter method over a generic query helper that forces callers to know table shape.
- Preserve behavior first; simplify module boundaries only when the migration exposes real duplicated persistence knowledge.
- When a query is complex but stable, raw SQL with bound parameters is acceptable.
- When a query is simple CRUD/upsert, prefer Sequel datasets over hand-written SQL strings.

## Risk Areas

- `SQLiteRankingRetention` currently builds dynamic SQL and quotes values manually.
- `SQLiteRankingReadModel` and `SQLiteProfileReadModel` have ranking/profile semantics encoded in SQL.
- `SQLiteJobProgress` has aggregation-heavy reporting logic.
- Schema migration must remain compatible with existing production database files.
- Long-running monthly jobs depend on transaction and resume semantics; transaction behavior must be verified before deployment.

## Completion Criteria

- [ ] Production code no longer instantiates or depends directly on `SQLite3::Database`.
- [ ] Context application/domain layers remain free of Sequel and SQLite details.
- [ ] All context SQLite adapters use either Sequel datasets or Sequel-bound SQL.
- [ ] Existing public behavior remains covered by tests.
- [ ] Architecture tests prevent Sequel from leaking inward.
- [ ] Normal pre-commit hook passes without bypassing verification.
