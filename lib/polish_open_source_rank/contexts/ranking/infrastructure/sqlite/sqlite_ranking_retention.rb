# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Ranking
      module Infrastructure
        module SQLite
          # Keeps complete contributor snapshots while limiting repository catalog noise.
          class SQLiteRankingRetention
            MINIMUM_REPOSITORY_STARS = Application::MonthlyRepositorySnapshotCollector::MINIMUM_REPOSITORY_STARS

            def initialize(database, catalog: Domain::LocationCatalog)
              @database = database
              @catalog = catalog
            end

            def prune(period)
              period_start = period.start_date.to_s

              transaction do
                prune_small_repository_stats(period_start)
                prune_small_organization_repository_stats(period_start)
                delete_orphaned_records
              end
            end

            private

            attr_reader :database

            def transaction(&)
              database.transaction(&)
            end

            def prune_small_repository_stats(period_start)
              execute(<<~SQL, [period_start])
                DELETE FROM repository_monthly_stats
                WHERE period_start = ?
                  AND stargazers_count < #{MINIMUM_REPOSITORY_STARS}
              SQL
            end

            def prune_small_organization_repository_stats(period_start)
              execute(<<~SQL, [period_start])
                DELETE FROM organization_repository_monthly_stats
                WHERE period_start = ?
                  AND stargazers_count < #{MINIMUM_REPOSITORY_STARS}
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
