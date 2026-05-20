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
              database.fetch_value(<<~SQL)
                SELECT MAX(period_start)
                FROM (
                  SELECT period_start FROM user_monthly_stats
                  UNION
                  SELECT period_start FROM repository_monthly_stats
                )
              SQL
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

            private

            attr_reader :database
          end
        end
      end
    end
  end
end
