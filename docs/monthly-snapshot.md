# Monthly Snapshot Architecture

The monthly snapshot use case turns source-platform profiles and repositories
into ranking-owned monthly snapshots. The public entry point is
`RunMonthlySnapshot#call(period, refresh:, scope:, use_snapshot_star_diff:,
existing_only:, backfill:)`; CLI and resume callers should not know candidate
queue shape, source search terms, repository enumeration style, or persistence
write order.

## Flow

1. `Interfaces::Composition::RankingJobFactory` builds source gateways, the
   SQLite-backed monthly store, work-event recording, and the monthly snapshot
   application graph.
2. `RunMonthlySnapshot` creates or resumes the run, delegates optional
   metric-only backfills, starts source-level snapshot work, retries retryable
   candidates once, prunes ranking noise, and marks the run finished or failed.
3. `MonthlySourceSnapshotRunner` owns source worker threads and the ordered
   source stages: process existing candidates, discover more candidates unless
   `existing_only` is set, then process newly discovered candidates.
4. `MonthlyCandidateDiscovery` searches users and organizations by location
   catalog terms and records normalized candidate rows.
5. `MonthlyUserCandidateProcessor` and
   `MonthlyOrganizationCandidateProcessor` fetch one source profile, classify
   location evidence, mark rejected/missing/failed candidates, and delegate
   accepted profiles to persistence.
6. `MonthlyProfileSnapshotWriter` records the accepted profile and monthly
   profile snapshot while hiding snapshot factory and store write ordering from
   candidate processors.
7. `MonthlyRepositorySnapshotCollector` enumerates contributor or organization
   repositories, records repository work events, filters repositories below the
   ranking star threshold, stores repository snapshots, and returns
   `Domain::RepositoryMetrics`.
8. `MonthlyRepositoryStarSnapshotPolicy` owns the choice between
   source-provided historical star snapshots, stored snapshot diffs, and
   source-provided monthly deltas.
9. `MonthlySourceMetricBackfill` handles existing-snapshot metric refreshes
   such as merged pull requests and organization members without running
   discovery.

## Boundary Rules

- Composition wires concrete collaborators. Application objects receive stores,
  sources, loggers, work-event recorders, and lower-level application
  collaborators through their constructors.
- `RunMonthlySnapshot` stays a facade. It must not create discovery,
  candidate-processing, profile-writing, repository-collection, or snapshot
  factory collaborators, and it must not grow a private method cluster.
- Source API differences stay below the source runner and repository
  collector. Callers ask for user or organization processing; they do not check
  whether a source exposes eager lists, streaming enumeration, or organization
  support.
- Store locking stays inside the collaborator that owns the write. Callers do
  not synchronize around lower-level store methods.
- Candidate processors own candidate statuses. New statuses or profile-fetch
  error handling belong there, not in the facade.
- Repository ranking policy belongs in the repository collector or a dedicated
  policy object. Retention should reference the same threshold constant instead
  of duplicating it.
- Backfill-only options stay in `MonthlySourceMetricBackfill`; they should not
  reopen discovery or repository collection.

## Quality Guardrails

The architecture specs protect the main monthly snapshot boundaries:

- ranking application code stays independent from SQLite, Sequel, web, network,
  and environment details;
- ranking use cases do not speak SQLite column names;
- `RunMonthlySnapshot` remains below the documented size target and avoids
  lower-level monthly snapshot collaborator construction;
- concrete monthly snapshot wiring lives under `Interfaces::Composition`.

Run `.githooks/pre-commit` before committing monthly snapshot changes. It runs
RuboCop, Reek, bundle audit, the full RSpec suite through Knapsack, and coverage
collation.
