# Refactor Milestones

This file tracks refactors that should reduce long-term complexity, not just
move code around. Mark a task done only after the change is implemented,
covered where useful, checked by the quality gate, and committed when the
milestone is complete.

## Milestone 1: Lock The Monthly Snapshot Contract

Goal: make the current `RunMonthlySnapshot` behavior easy to protect before
splitting responsibilities out of the class.

Responsibility map:

- Orchestration: `RunMonthlySnapshot#call`, run lifecycle, source workflow
  sequencing, retry attempts, and top-level failure handling.
- Discovery: `MonthlyCandidateDiscovery` owns catalog search terms, source user
  and organization search, candidate recording, discovery logging, and
  synchronized candidate writes.
- Candidate processing: `RunMonthlySnapshot` still owns pending batches,
  already-processed checks, profile loading, classification, status marking,
  per-candidate work events, and candidate-level failure handling.
- Persistence: `RunMonthlySnapshot` still owns accepted profile snapshots,
  repository snapshots, monthly contributor and organization stats, and snapshot
  factory usage.
- Repository metrics: `RunMonthlySnapshot` still owns repository enumeration,
  minimum-star filtering, source star snapshots, monthly delta selection, and
  `Domain::RepositoryMetrics` aggregation.
- Backfill: `MonthlySourceMetricBackfill` owns metric-only existing snapshot
  refresh paths.
- Observability: `MonthlySnapshotWorkflow` and lower collaborators share stage
  logs and timed work events until later milestones localize them further.

Stable public contract:

`RunMonthlySnapshot#call(period, refresh: false, scope: nil,
use_snapshot_star_diff: false, existing_only: false, backfill: {})` remains the
CLI and composition-facing use-case entry point. The extraction keeps discovery
below that boundary, so callers do not know search terms, candidate table shape,
source organization capability checks, logging format, or store locking rules.

- [x] Map the current responsibilities and classify them as orchestration,
      discovery, candidate processing, persistence, repository metrics,
      backfill, error handling, or observability.
- [x] Identify the public contract that must remain stable for CLI and
      composition callers: `call(period, refresh:, scope:,
      use_snapshot_star_diff:, existing_only:, backfill:)`.
- [x] Add or tighten high-value specs around run creation, refresh platforms,
      run completion, run failure, backfill-only execution, and source
      threading.
- [x] Add regression coverage for the user and organization candidate statuses:
      `processed`, `missing`, `rejected`, and `failed`.
- [x] Run Reek against the touched application files and remove new smells
      instead of suppressing them.
- [x] Run the full pre-commit hook and commit the completed milestone.

## Milestone 2: Extract Candidate Discovery

Goal: move source search and candidate recording behind a deeper application
collaborator while `RunMonthlySnapshot` keeps only workflow-level sequencing.

- [x] Introduce a `MonthlyCandidateDiscovery` application object that owns user
      and organization discovery for one source and period.
- [x] Keep location search-term knowledge inside the discovery object through
      the catalog interface, not in `RunMonthlySnapshot`.
- [x] Keep store synchronization and candidate-recording details hidden behind
      the discovery object or an explicit store gateway it owns.
- [x] Preserve source capability handling for organizations without exposing
      extra mode flags to callers.
- [x] Move discovery-specific logging into the discovery object with the same
      observable messages unless a spec documents the intentional change.
- [x] Add focused specs for user discovery, organization discovery, unsupported
      organization sources, and candidate login recording.
- [x] Run the full pre-commit hook and commit the completed milestone.

## Milestone 3: Extract Candidate Processing

Goal: isolate candidate retry, profile loading, classification, status marking,
and per-candidate work-event handling from the top-level snapshot runner.

- [x] Introduce a candidate processor that handles one user candidate and
      returns a stable status result.
- [x] Introduce an organization candidate processor only if it hides real
      differences; otherwise use a shared processor with role-specific
      dependencies instead of boolean mode flags.
- [x] Move processed-existing checks, `SourceNotFound` handling, failure
      marking, and failure logging into the processor boundary.
- [x] Keep classification policy in the application layer while source profile
      fetching and store status updates stay behind narrow collaborators.
- [x] Make invalid candidate states unrepresentable or localized, so callers do
      not repeat `platform`, `login`, and `source_id` fetch ceremony.
- [x] Add specs for refresh vs non-refresh behavior, missing source profiles,
      rejected non-Polish locations, successful persistence delegation, and
      failed candidate marking.
- [x] Run Reek against the new processors and avoid `UtilityFunction`,
      `FeatureEnvy`, and long parameter-list smells.
- [x] Run the full pre-commit hook and commit the completed milestone.

## Milestone 4: Extract Profile Snapshot Persistence

Goal: hide profile, repository, snapshot factory, and store-write details behind
one semantic operation for accepted contributors and organizations.

- [x] Introduce a `MonthlyProfileSnapshotWriter` or equivalent application
      collaborator with operations named around business intent, not storage
      mechanics.
- [x] Move contributor profile snapshot recording and contributor monthly
      snapshot recording out of `RunMonthlySnapshot`.
- [x] Move organization profile snapshot recording and organization monthly
      snapshot recording out of `RunMonthlySnapshot`.
- [x] Keep `MonthlySnapshotFactory` usage below the writer boundary so callers
      do not need to know snapshot object construction order.
- [x] Preserve thread-safe store writes without making every caller remember
      locking rules.
- [x] Add focused specs for contributor and organization profile persistence
      through the writer public contract.
- [x] Run the full pre-commit hook and commit the completed milestone.

## Milestone 5: Extract Repository Snapshot Collection

Goal: make repository enumeration, star snapshots, delta calculation,
minimum-star filtering, metrics aggregation, and repository snapshot writes a
cohesive module below profile persistence.

- [x] Introduce a repository snapshot collector that accepts an accepted profile
      and returns `Domain::RepositoryMetrics`.
- [x] Hide source API differences between eager repository lists and streaming
      repository enumeration inside the collector.
- [x] Hide contributor vs organization repository differences behind separate
      semantic entry points or role objects, not scattered conditionals.
- [x] Move `MINIMUM_REPOSITORY_STARS` ownership to the collector or a ranking
      policy object, then update retention references if needed.
- [x] Move star delta calculation into a dedicated policy that owns the choice
      between stored snapshot diffs and source-provided deltas.
- [x] Keep repository work-event recording near repository processing so the
      top-level runner does not know repository unit labels or stages.
- [x] Add specs for minimum-star filtering, zero-star repositories, stored
      snapshot diffs, source-provided deltas, contributor repositories, and
      organization repositories.
- [x] Run the full pre-commit hook and commit the completed milestone.

## Milestone 6: Shrink RunMonthlySnapshot To A Use-Case Facade

Goal: leave `RunMonthlySnapshot` as the stable monthly snapshot use case that
coordinates source-level workflow without owning lower-level decisions.

- [x] Replace private discovery, candidate-processing, profile-persistence, and
      repository methods with injected collaborators wired from composition.
- [x] Keep `RunMonthlySnapshot#call` responsible for run lifecycle,
      backfill-only delegation, source workflow sequencing, and top-level
      failure handling only.
- [x] Preserve `MonthlySnapshotWorkflow` usage only if it still hides real
      source-thread complexity; otherwise move threading behind a clearer
      source-runner collaborator.
- [x] Remove instance flags like `@use_snapshot_star_diff` and `@existing_only`
      when a request model or collaborator configuration can make the run
      context explicit.
- [x] Verify `RunMonthlySnapshot` has no broad private-method cluster and stays
      below the agreed size target.
- [x] Update composition specs to assert collaborator wiring without binding
      tests to construction internals.
- [x] Run Reek against the ranking application namespace and fix smells caused
      by the refactor.
- [x] Run the full pre-commit hook and commit the completed milestone.

## Milestone 7: Documentation And Architecture Guardrails

Goal: make the new boundaries discoverable and keep future changes from
rebuilding the same orchestrator god object.

- [x] Document the monthly snapshot flow and collaborator responsibilities in
      the nearest architecture or ranking documentation.
- [x] Add an architecture spec if dependency direction or package boundaries
      need enforcement after extraction.
- [x] Keep adapters humble: composition wires concrete collaborators, while
      application objects depend on plain interfaces and domain objects.
- [x] Record the size or smell expectations for monthly snapshot application
      objects where the project already tracks quality gates.
- [x] Run the full pre-commit hook and commit the completed milestone.
