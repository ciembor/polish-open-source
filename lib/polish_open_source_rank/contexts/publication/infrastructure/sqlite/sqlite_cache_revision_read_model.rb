# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Publication
      module Infrastructure
        module SQLite
          class SQLiteCacheRevisionReadModel
            def initialize(database)
              @database = database
            end

            def latest_period
              periods = database.dataset(:user_monthly_stats).select_map(:period_start) +
                        database.dataset(:repository_monthly_stats).select_map(:period_start)
              periods.max
            end

            def public_cache_revision(period_start)
              return unless period_start

              database.fetch_value(<<~SQL, [period_start, period_start, period_start])
                SELECT MAX(value)
                FROM (
                  SELECT MAX(updated_at) AS value
                  FROM user_monthly_stats
                  WHERE period_start = ?
                  UNION ALL
                  SELECT MAX(updated_at) AS value
                  FROM repository_monthly_stats
                  WHERE period_start = ?
                  UNION ALL
                  SELECT MAX(COALESCE(finished_at, started_at)) AS value
                  FROM sync_runs
                  WHERE period_start = ?
                )
              SQL
            end

            def recorded_period?(period_start)
              return false unless period_start

              database.dataset(:sync_runs).where(period_start: period_start).any?
            end

            private

            attr_reader :database
          end
        end
      end
    end
  end
end
