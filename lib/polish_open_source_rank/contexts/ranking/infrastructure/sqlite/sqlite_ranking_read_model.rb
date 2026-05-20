# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Ranking
      module Infrastructure
        module SQLite
          class SQLiteRankingReadModel
            def initialize(database, catalog: Domain::LocationCatalog)
              @database = database
              @catalog = catalog
            end

            def user_rankings(scope, period_start:)
              Domain::RankingPolicy::USER_RANKINGS.transform_values do |metric|
                ranked_users(scope, period_start, metric.column)
              end
            end

            def repository_rankings(scope, period_start:)
              Domain::RankingPolicy::REPOSITORY_RANKINGS.transform_values do |metric|
                ranked_repositories(scope, period_start, metric.column)
              end
            end

            def ranked_users(scope, period_start, order_column, limit: Domain::RankingPolicy::RANKING_LIMIT)
              sql_scope, params = user_scope(scope)
              database.fetch_all(<<~SQL, [period_start, *params])
                SELECT users.platform, users.login, users.name, users.email, users.homepage, users.html_url,
                       users.avatar_url, stats.city, stats.country, stats.public_repo_count, stats.total_stars,
                       stats.monthly_stars_delta, stats.public_activity_count
                FROM user_monthly_stats stats
                INNER JOIN users ON users.platform = stats.platform AND users.github_id = stats.user_github_id
                WHERE stats.period_start = ? AND #{sql_scope} #{trending_filter(order_column, 'stats')}
                ORDER BY stats.#{order_column} DESC, users.platform ASC, users.login COLLATE NOCASE ASC
                LIMIT #{Domain::RankingPolicy.bounded_limit(limit)}
              SQL
            end

            def ranked_repositories(scope, period_start, order_column, limit: Domain::RankingPolicy::RANKING_LIMIT)
              sql_scope, params = repository_scope(scope)
              database.fetch_all(<<~SQL, [period_start, *params])
                SELECT repositories.platform, repositories.full_name, repositories.name, repositories.description,
                       repositories.html_url, repositories.homepage, repositories.language, stats.owner_login,
                       stats.owner_city, stats.owner_country, stats.stargazers_count, stats.monthly_stars_delta
                FROM repository_monthly_stats stats
                INNER JOIN repositories
                  ON repositories.platform = stats.platform
                 AND repositories.github_id = stats.repository_github_id
                WHERE stats.period_start = ? AND #{sql_scope} #{trending_filter(order_column, 'stats')}
                ORDER BY stats.#{order_column} DESC, repositories.platform ASC,
                         repositories.full_name COLLATE NOCASE ASC
                LIMIT #{Domain::RankingPolicy.bounded_limit(limit)}
              SQL
            end

            private

            attr_reader :catalog, :database

            def trending_filter(order_column, table_alias)
              Domain::RankingPolicy.trending?(order_column) ? "AND #{table_alias}.monthly_stars_delta > 0" : ''
            end

            def user_scope(scope)
              return ['stats.country = ?', ['Poland']] if scope == 'poland'

              ['stats.city = ?', [catalog.city_name(scope)]]
            end

            def repository_scope(scope)
              return ['stats.owner_country = ?', ['Poland']] if scope == 'poland'

              ['stats.owner_city = ?', [catalog.city_name(scope)]]
            end
          end
        end
      end
    end
  end
end
