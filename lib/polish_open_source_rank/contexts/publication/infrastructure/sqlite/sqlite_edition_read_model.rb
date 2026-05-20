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
              database.fetch_all(<<~SQL)
                SELECT DISTINCT substr(period_start, 1, 4) AS year
                FROM sync_runs
                WHERE #{edition_period_condition}
                ORDER BY year DESC
              SQL
            end

            def monthly_editions(year, scope: 'poland')
              database.fetch_all(<<~SQL, [year.to_s]).map do |row|
                SELECT period_start
                FROM sync_runs
                WHERE #{edition_period_condition} AND substr(period_start, 1, 4) = ?
                ORDER BY period_start DESC
              SQL
                edition(row.fetch(:period_start), scope)
              end
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
                users_by_activity: ranking_read_model.ranked_user_metric(scope, period_start, :user_active, limit: 3)
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
                )
              SQL
            end
          end
        end
      end
    end
  end
end
