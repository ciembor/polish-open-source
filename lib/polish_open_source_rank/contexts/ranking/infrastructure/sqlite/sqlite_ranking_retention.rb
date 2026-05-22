# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Ranking
      module Infrastructure
        module SQLite
          # Keeps only rows needed to render top rankings and removes orphaned snapshot records.
          class SQLiteRankingRetention
            def initialize(database, catalog: Domain::LocationCatalog)
              @database = database
              @catalog = catalog
            end

            def prune(period)
              period_start = period.start_date.to_s

              transaction do
                prune_user_stats(period_start)
                prune_repository_stats(period_start)
                prune_organization_stats(period_start)
                prune_organization_repository_stats(period_start)
                delete_orphaned_records
              end
            end

            private

            attr_reader :catalog, :database

            def transaction(&)
              database.transaction(&)
            end

            def prune_user_stats(period_start)
              keep_sql, keep_params = ranking_union_sql(
                period_start: period_start,
                table: 'user_monthly_stats',
                id_column: 'platform, user_github_id',
                country_column: 'country',
                city_column: 'city',
                metrics: Domain::RankingPolicy::USER_RANKINGS.values,
                tie_breaker: Domain::RankingPolicy::USER_TIE_BREAKER
              )
              execute(<<~SQL, [period_start, *keep_params])
                DELETE FROM user_monthly_stats
                WHERE period_start = ?
                  AND (platform, user_github_id) NOT IN (#{keep_sql})
              SQL
            end

            def prune_repository_stats(period_start)
              keep_sql, keep_params = ranking_union_sql(
                period_start: period_start,
                table: 'repository_monthly_stats',
                id_column: 'platform, repository_github_id',
                country_column: 'owner_country',
                city_column: 'owner_city',
                metrics: Domain::RankingPolicy::REPOSITORY_RANKINGS.values,
                tie_breaker: Domain::RankingPolicy::REPOSITORY_TIE_BREAKER
              )
              execute(<<~SQL, [period_start, *keep_params])
                DELETE FROM repository_monthly_stats
                WHERE period_start = ?
                  AND (platform, repository_github_id) NOT IN (#{keep_sql})
              SQL
            end

            def prune_organization_stats(period_start)
              keep_sql, keep_params = ranking_union_sql(
                period_start: period_start,
                table: 'organization_monthly_stats',
                id_column: 'platform, organization_github_id',
                country_column: 'country',
                city_column: nil,
                metrics: Domain::RankingPolicy::ORGANIZATION_RANKINGS.values,
                tie_breaker: Domain::RankingPolicy::ORGANIZATION_TIE_BREAKER
              )
              execute(<<~SQL, [period_start, *keep_params])
                DELETE FROM organization_monthly_stats
                WHERE period_start = ?
                  AND (platform, organization_github_id) NOT IN (#{keep_sql})
              SQL
            end

            def prune_organization_repository_stats(period_start)
              keep_sql, keep_params = ranking_union_sql(
                period_start: period_start,
                table: 'organization_repository_monthly_stats',
                id_column: 'platform, repository_github_id',
                country_column: 'organization_country',
                city_column: nil,
                metrics: Domain::RankingPolicy::ORGANIZATION_REPOSITORY_RANKINGS.values,
                tie_breaker: Domain::RankingPolicy::ORGANIZATION_REPOSITORY_TIE_BREAKER
              )
              execute(<<~SQL, [period_start, *keep_params])
                DELETE FROM organization_repository_monthly_stats
                WHERE period_start = ?
                  AND (platform, repository_github_id) NOT IN (#{keep_sql})
              SQL
            end

            def ranking_union_sql(options)
              country_column = options.fetch(:country_column)
              city_column = options.fetch(:city_column)
              scopes = [[country_column, catalog::COUNTRY]]
              scopes += catalog::CITIES.map { |city| [city_column, city.fetch(:name)] } if city_column
              fragments = options.fetch(:metrics).product(scopes).map do |metric, scope|
                ranked_ids_sql(options, metric.column, scope)
              end
              [fragments.map(&:first).join("\nUNION\n"), fragments.flat_map(&:last)]
            end

            def ranked_ids_sql(options, metric, scope)
              id_column = options.fetch(:id_column)
              scope_column, scope_value = scope
              [<<~SQL, [options.fetch(:period_start), scope_value]]
                SELECT #{id_column}
                FROM (
                  SELECT #{id_column},
                         ROW_NUMBER() OVER (
                           ORDER BY #{metric} DESC, #{options.fetch(:tie_breaker)}
                         ) AS ranking_position
                  FROM #{options.fetch(:table)}
                  WHERE period_start = ?
                    AND #{scope_column} = ?
                )
                WHERE ranking_position <= #{Domain::RankingPolicy::RANKING_LIMIT}
              SQL
            end

            def delete_orphaned_records
              delete_orphaned_repositories
              delete_orphaned_organization_repositories
              delete_orphaned_users
              delete_orphaned_organizations
            end

            def delete_orphaned_repositories
              execute(<<~SQL)
                DELETE FROM repositories
                WHERE (platform, github_id) NOT IN (
                  SELECT DISTINCT platform, repository_github_id FROM repository_monthly_stats
                )
              SQL
            end

            def delete_orphaned_organization_repositories
              execute(<<~SQL)
                DELETE FROM organization_repositories
                WHERE (platform, github_id) NOT IN (
                  SELECT DISTINCT platform, repository_github_id FROM organization_repository_monthly_stats
                )
              SQL
            end

            def delete_orphaned_users
              execute(<<~SQL)
                DELETE FROM users
                WHERE (platform, github_id) NOT IN (
                  SELECT DISTINCT platform, user_github_id FROM user_monthly_stats
                )
                  AND (platform, github_id) NOT IN (
                    SELECT DISTINCT platform, owner_github_id FROM repositories
                  )
              SQL
            end

            def delete_orphaned_organizations
              execute(<<~SQL)
                DELETE FROM organizations
                WHERE (platform, github_id) NOT IN (
                  SELECT DISTINCT platform, organization_github_id FROM organization_monthly_stats
                )
                  AND (platform, github_id) NOT IN (
                    SELECT DISTINCT platform, organization_github_id FROM organization_repositories
                  )
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
