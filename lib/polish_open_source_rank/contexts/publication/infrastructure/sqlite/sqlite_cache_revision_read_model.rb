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
              explicit = database.fetch_value(
                "SELECT MAX(period_start) FROM public_snapshot_publications WHERE status = 'published'"
              )
              explicit || database.fetch_value(public_period_sql('MAX(sync_runs.period_start)'))
            end

            def public_cache_revision(period_start)
              return unless period_start

              database.fetch_value(public_cache_revision_sql, [period_start] * (revision_tables.length + 1))
            end

            def recorded_period?(period_start)
              return false unless period_start

              return published_period?(period_start) if explicit_publications?

              database.fetch_value(public_period_sql('1', 'sync_runs.period_start = ?'), [period_start]) == 1
            end

            private

            attr_reader :database

            def published_period?(period_start)
              return false unless explicit_publications?

              database.fetch_value(<<~SQL, [period_start]) == 1
                SELECT 1
                FROM public_snapshot_publications
                WHERE period_start = ?
                  AND status IN ('published', 'superseded')
              SQL
            end

            def explicit_publications?
              database.fetch_value(published_publication_count_sql).to_i.positive?
            end

            def published_publication_count_sql
              "SELECT COUNT(*) FROM public_snapshot_publications WHERE status = 'published'"
            end

            def revision_tables
              %i[
                user_monthly_stats
                repository_monthly_stats
                organization_monthly_stats
                organization_repository_monthly_stats
                published_badges
              ]
            end

            def public_period_sql(select_expression, extra_condition = nil)
              conditions = ["sync_runs.status = 'finished'", public_period_stats_condition]
              conditions << extra_condition if extra_condition

              <<~SQL
                SELECT #{select_expression}
                FROM sync_runs
                WHERE #{conditions.join("\n  AND ")}
              SQL
            end

            def public_period_stats_condition
              <<~SQL
                (
                  EXISTS (
                    SELECT 1 FROM user_monthly_stats user_stats
                    WHERE user_stats.period_start = sync_runs.period_start
                  )
                  OR EXISTS (
                    SELECT 1 FROM repository_monthly_stats repository_stats
                    WHERE repository_stats.period_start = sync_runs.period_start
                  )
                  OR EXISTS (
                    SELECT 1 FROM organization_monthly_stats organization_stats
                    WHERE organization_stats.period_start = sync_runs.period_start
                  )
                  OR EXISTS (
                    SELECT 1 FROM organization_repository_monthly_stats organization_repository_stats
                    WHERE organization_repository_stats.period_start = sync_runs.period_start
                  )
                )
              SQL
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
