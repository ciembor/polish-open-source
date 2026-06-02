# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Ranking
      module Application
        # Provides shared dependencies for monthly candidate processors.
        class MonthlyCandidateProcessor
          def initialize(store:, store_mutex:, classifier:, profile_writer:, logger:, work_events:)
            @store = store
            @store_mutex = store_mutex
            @classifier = classifier
            @profile_writer = profile_writer
            @logger = logger
            @work_events = work_events
          end

          private

          attr_reader :classifier, :logger, :profile_writer, :store, :store_mutex, :work_events

          def record_work_event(request, &)
            work_events.record_timed(
              period_start: request.period.start_date.to_s,
              job_kind: 'monthly',
              **request.work_attributes, &
            )
          end

          def with_store(&)
            store_mutex.synchronize(&)
          end
        end
      end
    end
  end
end
