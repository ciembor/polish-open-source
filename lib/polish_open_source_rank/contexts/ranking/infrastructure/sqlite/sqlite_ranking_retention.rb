# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Ranking
      module Infrastructure
        module SQLite
          class SQLiteRankingRetention
            RANKING_LIMIT = 100

            def initialize(database, catalog: Domain::LocationCatalog)
              @database = database
              @catalog = catalog
            end

            def prune(period)
              period_start = period.start_date.to_s

              transaction do
                prune_user_stats(period_start)
                prune_repository_stats(period_start)
                delete_orphaned_records
              end
            end

            private

            attr_reader :catalog, :database

            def transaction(&)
              database.transaction(&)
            end

            def prune_user_stats(period_start)
              keep_sql = ranking_union_sql(
                period_start: period_start,
                table: 'user_monthly_stats',
                id_column: 'platform, user_github_id',
                country_column: 'country',
                city_column: 'city',
                metrics: %w[total_stars monthly_stars_delta public_activity_count],
                tie_breaker: 'login COLLATE NOCASE ASC'
              )
              execute(<<~SQL, [period_start])
                DELETE FROM user_monthly_stats
                WHERE period_start = ?
                  AND (platform, user_github_id) NOT IN (#{keep_sql})
              SQL
            end

            def prune_repository_stats(period_start)
              keep_sql = ranking_union_sql(
                period_start: period_start,
                table: 'repository_monthly_stats',
                id_column: 'platform, repository_github_id',
                country_column: 'owner_country',
                city_column: 'owner_city',
                metrics: %w[stargazers_count monthly_stars_delta],
                tie_breaker: 'owner_login COLLATE NOCASE ASC, repository_github_id ASC'
              )
              execute(<<~SQL, [period_start])
                DELETE FROM repository_monthly_stats
                WHERE period_start = ?
                  AND (platform, repository_github_id) NOT IN (#{keep_sql})
              SQL
            end

            def ranking_union_sql(options)
              scopes = [[options.fetch(:country_column), catalog::COUNTRY]] +
                       catalog::CITIES.map { |city| [options.fetch(:city_column), city.fetch(:name)] }
              options.fetch(:metrics).product(scopes).map do |metric, (scope_column, scope_value)|
                ranked_ids_sql(options.merge(metric: metric, scope_column: scope_column, scope_value: scope_value))
              end.join("\nUNION\n")
            end

            def ranked_ids_sql(options)
              <<~SQL
                SELECT #{options.fetch(:id_column)}
                FROM (
                  SELECT #{options.fetch(:id_column)},
                         ROW_NUMBER() OVER (
                           ORDER BY #{options.fetch(:metric)} DESC, #{options.fetch(:tie_breaker)}
                         ) AS ranking_position
                  FROM #{options.fetch(:table)}
                  WHERE period_start = #{sql_string(options.fetch(:period_start))}
                    AND #{options.fetch(:scope_column)} = #{sql_string(options.fetch(:scope_value))}
                )
                WHERE ranking_position <= #{RANKING_LIMIT}
              SQL
            end

            def sql_string(value)
              "'#{SQLite3::Database.quote(value.to_s)}'"
            end

            def delete_orphaned_records
              execute(<<~SQL)
                DELETE FROM repositories
                WHERE (platform, github_id) NOT IN (
                  SELECT DISTINCT platform, repository_github_id FROM repository_monthly_stats
                )
              SQL
              execute(<<~SQL)
                DELETE FROM users
                WHERE (platform, github_id) NOT IN (SELECT DISTINCT platform, user_github_id FROM user_monthly_stats)
                  AND (platform, github_id) NOT IN (SELECT DISTINCT platform, owner_github_id FROM repositories)
              SQL
            end

            def execute(sql, params = [])
              database.execute(sql, params)
            end
          end
        end
      end
    end
  end
end
