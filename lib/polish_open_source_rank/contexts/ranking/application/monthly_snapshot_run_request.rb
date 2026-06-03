# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Ranking
      module Application
        # Immutable request context for one monthly snapshot run.
        MonthlySnapshotRunRequest = Struct.new(
          :period,
          :refresh,
          :scope,
          :existing_only,
          :backfill,
          keyword_init: true
        ) do
          def refresh_platforms(sources)
            return [] unless refresh?

            sources.map(&:platform)
          end

          def retry_only
            self.class.new(
              period: period,
              refresh: false,
              scope: scope,
              existing_only: true,
              backfill: {}
            )
          end

          def active_candidate_types
            case scope
            when :users then [:users]
            when :organizations then [:organizations]
            else %i[users organizations]
            end
          end

          def user_sources?
            scope != :organizations
          end

          def organization_sources?
            scope != :users
          end

          def source_metric_backfill_only?
            existing_only? && backfill.value?(true)
          end

          def existing_only?
            existing_only
          end

          def refresh?
            refresh
          end
        end
      end
    end
  end
end
