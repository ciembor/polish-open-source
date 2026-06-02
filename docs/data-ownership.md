# SQLite Data Ownership

The application uses one SQLite database. The schema stays in one file because
transactional monthly publication, package scans, job monitoring, and community
actions all run in the same deployable process. Ownership is still explicit:
each table in `lib/polish_open_source_rank/infrastructure/sqlite_schema.sql`
has an `@owner` marker before `CREATE TABLE`, and shared tables list
cross-context `@readers`.

Ownership means the context that may change table shape, write semantics,
retention, and indexes. Readers may depend on a table through their own
SQLite-backed read model or repository, but they do not own the persistence
contract.

## Owners

| Owner | Tables | Notes |
| --- | --- | --- |
| `ranking` | `sync_runs`, `candidate_users`, `candidate_organizations`, `users`, `organizations`, `user_monthly_stats`, `organization_monthly_stats`, `repositories`, `organization_repositories`, `repository_monthly_stats`, `organization_repository_monthly_stats`, `repository_star_observations`, `organization_repository_star_observations`, `api_request_events` | Monthly source crawl and ranking owns platform identities, snapshots, source request telemetry, and ranking retention. |
| `publication` | `public_snapshot_publications`, `published_badges` | Publication owns the currently public period and materialized badge state. It reads ranking snapshots to render public pages. |
| `packages` | `package_crawl_runs`, `package_repository_scans`, `package_manifests`, `registry_packages`, `registry_package_links`, `registry_package_snapshots` | Package ranking owns manifest scans, registry resolution, and package metric snapshots. |
| `community` | `discord_connections`, `discord_invites`, `discord_sync_jobs` | Community owns Discord account links, invites, and sync jobs. |
| `operations` | `crawl_job_runs`, `job_work_events` | Operations owns resumable command runs and work-event telemetry used by internal monitoring. |

## Shared Ranking Reads

The ranking-owned profile and ranking tables are intentionally shared public
read models. They are written by monthly ranking jobs and read by:

- `publication` for rankings, profile pages, editions, cache revision, and
  badge materialization.
- `languages` for language and repository-language ranking pages.
- `packages` for finding the already ranked repositories that should be scanned
  for manifests.
- `community` for contributor access checks before Discord actions.
- `operations` for internal job progress counts.

Those dependencies should stay inside infrastructure adapters such as
`SQLiteProfileReadModel`, `SQLiteLanguageRankingReadModel`,
`SQLitePackageRepositoryQueue`, and `SQLiteJobProgressReadModel`. Application
use cases should receive plain request/response objects and should not speak
table or column names.

## Change Convention

When changing SQLite persistence:

1. Decide the owner first. Add `-- @owner <context>` before every new
   `CREATE TABLE`. Add `-- @readers ...` only for existing, intentional
   cross-context reads.
2. Keep `sqlite_schema.sql` as the executable current schema. Do not split it
   into context files unless that removes real coupling or enables a separate
   lifecycle.
3. Put compatibility migrations in `PlatformSchemaMigration` when an existing
   production database needs data-preserving shape changes.
4. Add or update regression specs before touching published ranking, profile,
   badge, package, or publication tables. Prefer public-contract specs for the
   owning repository/read model over assertions that expose internal SQL.
5. Hide volatile joins, ranking windows, status calculations, and column aliases
   inside semantic read-model methods. Callers should ask for profiles, rankings,
   package queues, progress, or badges rather than constructing SQL fragments.
6. Add or update indexes next to the schema change that needs them, and record
   query-plan expectations in `docs/performance.md` for public hot paths.

If a reader needs a new table or column from another context, first consider
whether the owner can expose a deeper read operation that hides the storage
detail. A direct cross-context read is acceptable only when the dependency is a
stable read model and the owner remains responsible for the table contract.
