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
              periods = revision_tables.flat_map do |table|
                database.dataset(table).select_map(:period_start)
              end
              periods.max
            end

            def public_cache_revision(period_start)
              return unless period_start

              database.fetch_value(public_cache_revision_sql, [period_start] * (revision_tables.length + 1))
            end

            def recorded_period?(period_start)
              return false unless period_start

              database.dataset(:sync_runs).where(period_start: period_start).any?
            end

            private

            attr_reader :database

            def revision_tables
              %i[
                user_monthly_stats
                repository_monthly_stats
                organization_monthly_stats
                organization_repository_monthly_stats
              ]
            end

            def public_cache_revision_sql
              stats_queries = revision_tables.map do |table|
                <<~SQL
                  SELECT MAX(updated_at) AS value
                  FROM #{table}
                  WHERE period_start = ?
                SQL
              end

              <<~SQL
                SELECT MAX(value)
                FROM (
                  #{stats_queries.join("UNION ALL\n")}
                  UNION ALL
                  SELECT MAX(COALESCE(finished_at, started_at)) AS value
                  FROM sync_runs
                  WHERE period_start = ?
                )
              SQL
            end
          end
        end
      end
    end
  end
end
