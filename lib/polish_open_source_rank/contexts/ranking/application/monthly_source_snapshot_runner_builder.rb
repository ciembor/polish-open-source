# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Ranking
      module Application
        # Wires the source runner collaborators for application tests and composition.
        class MonthlySourceSnapshotRunnerBuilder
          def initialize(store:, sources:, classifier:, catalog:, logger:, work_events:)
            @store = store
            @sources = sources
            @classifier = classifier
            @catalog = catalog
            @logger = logger
            @work_events = work_events
            @store_mutex = Mutex.new
          end

          def build
            MonthlySourceSnapshotRunner.new(
              store: store,
              sources: sources,
              logger: logger,
              candidate_discovery: candidate_discovery,
              candidate_processors: candidate_processors,
              store_mutex: store_mutex
            )
          end

          private

          attr_reader :catalog, :classifier, :logger, :sources, :store, :store_mutex, :work_events

          def candidate_discovery
            MonthlyCandidateDiscovery.new(
              store: store,
              catalog: catalog,
              logger: logger,
              store_mutex: store_mutex
            )
          end

          def candidate_processors
            MonthlySourceSnapshotRunner::CandidateProcessors.new(
              user: user_candidate_processor,
              organization: organization_candidate_processor
            )
          end

          def user_candidate_processor
            MonthlyUserCandidateProcessor.new(
              **candidate_processor_dependencies,
              profile_writer: profile_writer
            )
          end

          def organization_candidate_processor
            MonthlyOrganizationCandidateProcessor.new(
              **candidate_processor_dependencies,
              profile_writer: profile_writer
            )
          end

          def candidate_processor_dependencies
            {
              store: store,
              store_mutex: store_mutex,
              classifier: classifier,
              logger: logger,
              work_events: work_events
            }
          end

          def profile_writer
            @profile_writer ||= MonthlyProfileSnapshotWriter.new(
              store: store,
              store_mutex: store_mutex,
              work_events: work_events,
              snapshot_factory: MonthlySnapshotFactory.new
            )
          end
        end
      end
    end
  end
end
