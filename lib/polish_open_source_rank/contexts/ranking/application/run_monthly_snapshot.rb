# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Ranking
      module Application
        class RunMonthlySnapshot
          BATCH_SIZE = MonthlySourceSnapshotRunner::BATCH_SIZE

          def initialize(store:, sources:, source_runner:, source_metric_backfill:)
            @store = store
            @sources = sources
            @source_runner = source_runner
            @source_metric_backfill = source_metric_backfill
          end

          def call(period, refresh: false, scope: nil, existing_only: false, backfill: {})
            request = MonthlySnapshotRunRequest.new(
              period: period,
              refresh: refresh,
              scope: scope,
              existing_only: existing_only,
              backfill: backfill
            )
            return source_metric_backfill.call(period, scope: scope, **backfill) if request.source_metric_backfill_only?

            refresh_platforms = request.refresh_platforms(sources)
            run_id = store.create_run(period, refresh_platforms: refresh_platforms)
            return unless run_id

            source_runner.call(request, refresh_platforms: refresh_platforms)

            complete_run(request, run_id)
          rescue StandardError => e
            store.fail_run(run_id, "#{e.class}: #{e.message}") if run_id
            raise
          end

          private

          attr_reader :source_metric_backfill, :source_runner, :sources, :store

          def complete_run(request, run_id)
            if source_retryable_candidates?(request)
              store.create_run(request.period, refresh_platforms: [])
              source_runner.call(request.retry_only, refresh_platforms: [])
              return store.fail_run(run_id, 'Retryable candidates remain') if source_retryable_candidates?(request)
            end
            return if store.retryable_candidates?(request.period)

            store.prune_rankings(request.period)
            store.finish_run(run_id)
          end

          def source_retryable_candidates?(request)
            store.retryable_candidates?(
              request.period,
              platforms: source_runner.source_platforms,
              candidate_types: request.active_candidate_types
            )
          end
        end
      end
    end
  end
end
