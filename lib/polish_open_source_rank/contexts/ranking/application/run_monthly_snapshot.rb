# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Ranking
      module Application
        class RunMonthlySnapshot
          include MonthlySnapshotWorkflow

          BATCH_SIZE = 50
          MINIMUM_REPOSITORY_STARS = 5
          def initialize(store:, sources:, classifier: Domain::LocationClassifier.new,
                         catalog: Domain::LocationCatalog, logger: $stdout,
                         work_events: Operations::Application::JobWorkEventRecorder.new)
            @store = store
            @sources = sources
            @classifier = classifier
            @logger = MonthlySnapshotLogger.new(logger)
            @store_mutex = Mutex.new
            @profile_snapshot_writer = build_profile_snapshot_writer(work_events)
            @user_candidate_processor = build_user_candidate_processor(work_events)
            @organization_candidate_processor = build_organization_candidate_processor(work_events)
            @candidate_discovery = build_candidate_discovery(catalog)
            @source_metric_backfill = build_source_metric_backfill(work_events)
          end

          def call(period, refresh: false, scope: nil, use_snapshot_star_diff: false, existing_only: false,
                   backfill: {})
            @scope = scope
            @use_snapshot_star_diff = use_snapshot_star_diff
            @existing_only = existing_only
            if source_metric_backfill_only?(backfill)
              return source_metric_backfill.call(period, scope: scope, **backfill)
            end

            refresh_platforms = refresh ? sources.map(&:platform) : []
            run_id = store.create_run(period, refresh_platforms: refresh_platforms)
            return unless run_id

            run_source_snapshots(period, refresh_platforms: refresh_platforms)

            complete_run(period, run_id)
          rescue StandardError => e
            store.fail_run(run_id, "#{e.class}: #{e.message}") if run_id
            raise
          end

          private

          attr_reader :candidate_discovery, :logger, :organization_candidate_processor, :profile_snapshot_writer,
                      :source_metric_backfill, :sources, :store, :store_mutex, :user_candidate_processor

          def build_profile_snapshot_writer(work_events)
            MonthlyProfileSnapshotWriter.new(
              store: store,
              store_mutex: store_mutex,
              work_events: work_events,
              minimum_repository_stars: MINIMUM_REPOSITORY_STARS
            )
          end

          def build_user_candidate_processor(work_events)
            MonthlyUserCandidateProcessor.new(
              store: store,
              store_mutex: store_mutex,
              classifier: @classifier,
              profile_writer: profile_snapshot_writer,
              logger: logger,
              work_events: work_events
            )
          end

          def build_organization_candidate_processor(work_events)
            MonthlyOrganizationCandidateProcessor.new(
              store: store,
              store_mutex: store_mutex,
              classifier: @classifier,
              profile_writer: profile_snapshot_writer,
              logger: logger,
              work_events: work_events
            )
          end

          def build_candidate_discovery(catalog)
            MonthlyCandidateDiscovery.new(
              store: store,
              catalog: catalog,
              logger: logger,
              store_mutex: store_mutex
            )
          end

          def build_source_metric_backfill(work_events)
            MonthlySourceMetricBackfill.new(
              store: store,
              sources: sources,
              logger: logger,
              work_events: work_events
            )
          end

          def discover_source_candidates(period, source)
            candidate_discovery.discover_users(period, source)
          end

          def discover_source_organizations(period, source)
            candidate_discovery.discover_organizations(period, source)
          end

          def process_source_candidates(period, source, refresh:)
            loop do
              candidates = with_store { store.pending_candidates(period, platform: source.platform, limit: BATCH_SIZE) }
              break if candidates.empty?

              log(source, "processing #{candidates.length} candidates")
              candidates.each do |candidate|
                user_candidate_processor.process(
                  period,
                  source,
                  candidate,
                  refresh: refresh,
                  use_snapshot_star_diff: use_snapshot_star_diff?
                )
              end
            end
            log(source, 'candidate processing finished')
          end

          def process_source_organizations(period, source, refresh:)
            return unless source.supports_organizations?

            loop do
              candidates = pending_organization_candidates(period, source)
              break if candidates.empty?

              log(source, "processing #{candidates.length} organizations")
              candidates.each do |candidate|
                organization_candidate_processor.process(
                  period,
                  source,
                  candidate,
                  refresh: refresh,
                  use_snapshot_star_diff: use_snapshot_star_diff?
                )
              end
            end
            log(source, 'organization processing finished')
          end

          def pending_organization_candidates(period, source)
            with_store do
              store.pending_organization_candidates(period, platform: source.platform, limit: BATCH_SIZE)
            end
          end

          def source_metric_backfill_only?(backfill)
            @existing_only && backfill.value?(true)
          end

          def use_snapshot_star_diff?
            @use_snapshot_star_diff
          end

          def with_store(&)
            store_mutex.synchronize(&)
          end

          def log(source, message)
            logger.puts "[#{source.platform}] #{message}"
          end
        end
      end
    end
  end
end
