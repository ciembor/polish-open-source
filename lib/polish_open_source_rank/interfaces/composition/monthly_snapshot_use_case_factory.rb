# frozen_string_literal: true

module PolishOpenSourceRank
  module Interfaces
    module Composition
      # Wires monthly ranking application objects to infrastructure-facing adapters.
      class MonthlySnapshotUseCaseFactory
        def initialize(store:, sources:, logger:, work_events:)
          @store = store
          @sources = sources
          @logger = logger
          @work_events = work_events
          @store_mutex = Mutex.new
        end

        def run_monthly_snapshot
          Contexts::Ranking::Application::RunMonthlySnapshot.new(
            store: store,
            sources: sources,
            source_runner: source_runner,
            source_metric_backfill: source_metric_backfill
          )
        end

        private

        attr_reader :logger, :sources, :store, :store_mutex, :work_events

        def source_runner
          Contexts::Ranking::Application::MonthlySourceSnapshotRunner.new(
            store: store,
            sources: sources,
            logger: logger,
            candidate_discovery: candidate_discovery,
            candidate_processors: candidate_processors,
            store_mutex: store_mutex
          )
        end

        def candidate_discovery
          Contexts::Ranking::Application::MonthlyCandidateDiscovery.new(
            store: store,
            catalog: Contexts::Ranking::Domain::LocationCatalog,
            logger: logger,
            store_mutex: store_mutex
          )
        end

        def candidate_processors
          Contexts::Ranking::Application::MonthlySourceSnapshotRunner::CandidateProcessors.new(
            user: user_candidate_processor,
            organization: organization_candidate_processor
          )
        end

        def user_candidate_processor
          Contexts::Ranking::Application::MonthlyUserCandidateProcessor.new(
            **candidate_processor_dependencies,
            profile_writer: profile_writer
          )
        end

        def organization_candidate_processor
          Contexts::Ranking::Application::MonthlyOrganizationCandidateProcessor.new(
            **candidate_processor_dependencies,
            profile_writer: profile_writer
          )
        end

        def candidate_processor_dependencies
          {
            store: store,
            store_mutex: store_mutex,
            classifier: Contexts::Ranking::Domain::LocationClassifier.new,
            logger: logger,
            work_events: work_events
          }
        end

        def profile_writer
          @profile_writer ||= begin
            snapshot_factory = Contexts::Ranking::Application::MonthlySnapshotFactory.new
            Contexts::Ranking::Application::MonthlyProfileSnapshotWriter.new(
              store: store,
              store_mutex: store_mutex,
              snapshot_factory: snapshot_factory,
              repository_collector: repository_collector(snapshot_factory)
            )
          end
        end

        def repository_collector(snapshot_factory)
          Contexts::Ranking::Application::MonthlyRepositorySnapshotCollector.new(
            store: store,
            store_mutex: store_mutex,
            work_events: work_events,
            snapshot_factory: snapshot_factory
          )
        end

        def source_metric_backfill
          Contexts::Ranking::Application::MonthlySourceMetricBackfill.new(
            store: store,
            sources: sources,
            logger: logger,
            work_events: work_events
          )
        end
      end
    end
  end
end
