# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Publication
      module Infrastructure
        module SQLite
          class SQLiteEditionReadModel
            def initialize(database, ranking_read_model: nil)
              @database = database
              @ranking_read_model = ranking_read_model || default_ranking_read_model
            end

            def years
              edition_period_starts
                .map { |period_start| { year: period_start[0, 4] } }
                .uniq
            end

            def edition_years
              years
            end

            def monthly_editions(year, scope: 'poland')
              edition_period_starts
                .select { |period_start| period_start.start_with?(year.to_s) }
                .map { |period_start| edition(period_start, scope) }
            end

            private

            attr_reader :database, :ranking_read_model

            def default_ranking_read_model
              Contexts::Ranking::Infrastructure::SQLite::SQLiteRankingReadModel.new(database)
            end

            def edition(period_start, scope)
              {
                period_start: period_start,
                repositories: ranking_read_model.ranked_repository_metric(
                  scope, period_start, :repository_top, limit: 3
                ),
                users_by_stars: ranking_read_model.ranked_user_metric(scope, period_start, :user_top, limit: 3),
                organizations_by_stars: ranking_read_model.ranked_organization_metric(
                  scope, period_start, :organization_top, limit: 3
                )
              }
            end

            def edition_period_condition
              <<~SQL
                (
                  EXISTS (
                    SELECT 1
                    FROM user_monthly_stats user_stats
                    WHERE user_stats.period_start = sync_runs.period_start
                  )
                  OR EXISTS (
                    SELECT 1
                    FROM repository_monthly_stats repository_stats
                    WHERE repository_stats.period_start = sync_runs.period_start
                  )
                  OR EXISTS (
                    SELECT 1
                    FROM organization_monthly_stats organization_stats
                    WHERE organization_stats.period_start = sync_runs.period_start
                  )
                )
              SQL
            end

            def edition_period_starts
              return explicit_edition_period_starts if explicit_publications?

              database.fetch_all(<<~SQL)
                SELECT period_start
                FROM sync_runs
                WHERE sync_runs.status = 'finished'
                  AND #{edition_period_condition}
                ORDER BY period_start DESC
              SQL
                      .map { |row| row.fetch(:period_start) }
            end

            def explicit_publications?
              database.fetch_value(published_publication_count_sql).to_i.positive?
            end

            def published_publication_count_sql
              "SELECT COUNT(*) FROM public_snapshot_publications WHERE status = 'published'"
            end

            def explicit_edition_period_starts
              database.fetch_all(<<~SQL)
                SELECT period_start
                FROM public_snapshot_publications
                WHERE status IN ('published', 'superseded')
                ORDER BY period_start DESC
              SQL
                      .map { |row| row.fetch(:period_start) }
            end
          end
        end
      end
    end
  end
end
