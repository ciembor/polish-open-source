# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Infrastructure
        module SQLite
          class SQLitePackageRankingReadModel
            DEFAULT_LIMIT = 100
            MAX_LIMIT = 100
            METRIC_EXPRESSIONS = Shared::Infrastructure::SQLite::SqlExpressionMap.new(
              {
                downloads_30d: 'snapshots.downloads_30d',
                downloads_total: 'snapshots.downloads_total',
                dependents_count: 'snapshots.dependents_count',
                repository_stars_count:
                  'MAX(COALESCE(user_stats.stargazers_count, organization_stats.stargazers_count))',
                repository_stars_delta:
                  'MAX(COALESCE(user_stats.monthly_stars_delta, organization_stats.monthly_stars_delta))'
              },
              name: 'package ranking metric expression'
            )

            def initialize(database)
              @database = database
            end

            def ecosystems(period_start:, repository_kind: nil)
              database.fetch_all(ecosystems_sql(repository_kind), ecosystems_bindings(period_start, repository_kind))
                      .map { |row| row.fetch(:ecosystem) }
            end

            def ecosystem_cards(period_start:)
              database.fetch_all(ecosystem_cards_sql, [period_start, period_start])
            end

            def rankings(ecosystem:, period_start:, limit: DEFAULT_LIMIT, repository_kind: nil)
              validate_repository_kind!(repository_kind)
              metrics = Domain::PackageRankingMetric.keys(ecosystem: ecosystem)
              rows = ranking_candidates(
                ecosystem: ecosystem,
                period_start: period_start,
                repository_kind: repository_kind
              )

              metrics.to_h do |metric|
                [metric.to_sym, sort_rankings(rows, metric, limit)]
              end
            end

            def ranked_packages(ecosystem:, period_start:, metric:, scope: 'poland', limit: DEFAULT_LIMIT,
                                repository_kind: nil)
              validate_metric!(metric)
              validate_ecosystem_metric!(ecosystem, metric)
              validate_repository_kind!(repository_kind)
              return [] unless scope == 'poland'

              database.fetch_all(
                ranked_packages_sql(metric, limit, repository_kind),
                ranked_packages_bindings(period_start, ecosystem, repository_kind)
              )
            end

            def package_profile(ecosystem:, package_name:, period_start:)
              rows = database.fetch_all(package_profile_sql, [period_start, ecosystem, package_name.to_s.downcase])
              return if rows.empty?

              package_profile_from(rows)
            end

            private

            attr_reader :database

            def ecosystems_sql(repository_kind)
              <<~SQL
                SELECT DISTINCT snapshots.ecosystem
                FROM registry_package_snapshots snapshots
                INNER JOIN registry_packages packages
                  ON packages.ecosystem = snapshots.ecosystem
                 AND packages.normalized_package_name = snapshots.normalized_package_name
                #{repository_link_joins(repository_kind)}
                WHERE snapshots.period_start = ?
                  AND packages.status = 'active'
                  #{repository_kind_filter(repository_kind)}
                ORDER BY snapshots.ecosystem ASC
              SQL
            end

            def ecosystems_bindings(period_start, repository_kind)
              bindings = [period_start]
              bindings << repository_kind if repository_kind
              bindings
            end

            def ranked_packages_sql(metric, limit, repository_kind)
              <<~SQL
                SELECT snapshots.ecosystem,
                       packages.package_name,
                       packages.normalized_package_name,
                       packages.registry_url,
                       packages.repository_url,
                       packages.homepage_url,
                       packages.license,
                       packages.latest_version,
                       snapshots.downloads_30d,
                       snapshots.downloads_total,
                       snapshots.dependents_count,
                       snapshots.dependent_repositories_count,
                       MAX(COALESCE(user_stats.stargazers_count, organization_stats.stargazers_count)) AS repository_stars_count,
                       MAX(COALESCE(user_stats.monthly_stars_delta, organization_stats.monthly_stars_delta)) AS repository_stars_delta,
                       snapshots.latest_release_at,
                       COUNT(DISTINCT scans.id) AS linked_repository_count,
                       MIN(scans.full_name) AS repository_full_name,
                       MIN(scans.repository_kind) AS repository_kind,
                       MIN(scans.platform) AS repository_platform,
                       #{owner_login_sql('MIN(scans.full_name)')} AS repository_owner_login
                FROM registry_package_snapshots snapshots
                INNER JOIN registry_packages packages
                  ON packages.ecosystem = snapshots.ecosystem
                 AND packages.normalized_package_name = snapshots.normalized_package_name
                LEFT JOIN registry_package_links links
                  ON links.ecosystem = packages.ecosystem
                 AND links.normalized_package_name = packages.normalized_package_name
                 AND links.matched = 1
                LEFT JOIN package_manifests manifests ON manifests.id = links.manifest_id
                LEFT JOIN package_repository_scans scans ON scans.id = manifests.repository_scan_id
                LEFT JOIN repository_monthly_stats user_stats
                  ON scans.repository_kind = 'user'
                 AND user_stats.period_start = snapshots.period_start
                 AND user_stats.platform = scans.platform
                 AND user_stats.repository_github_id = scans.repository_source_id
                LEFT JOIN organization_repository_monthly_stats organization_stats
                  ON scans.repository_kind = 'organization'
                 AND organization_stats.period_start = snapshots.period_start
                 AND organization_stats.platform = scans.platform
                 AND organization_stats.repository_github_id = scans.repository_source_id
                WHERE snapshots.period_start = ?
                  AND snapshots.ecosystem = ?
                  AND packages.status = 'active'
                  #{repository_kind_filter(repository_kind)}
                GROUP BY snapshots.ecosystem, packages.normalized_package_name
                HAVING #{metric_filter_sql(metric)}
                ORDER BY #{metric_expression(metric)} DESC, packages.package_name COLLATE NOCASE ASC
                LIMIT #{bounded_limit(limit)}
              SQL
            end

            def ranked_packages_bindings(period_start, ecosystem, repository_kind)
              bindings = [period_start, ecosystem]
              bindings << repository_kind if repository_kind
              bindings
            end

            def ranking_candidates(ecosystem:, period_start:, repository_kind:)
              database.fetch_all(
                ranking_candidates_sql(repository_kind),
                ranked_packages_bindings(period_start, ecosystem, repository_kind)
              )
            end

            def ranking_candidates_sql(repository_kind)
              <<~SQL
                SELECT snapshots.ecosystem,
                       packages.package_name,
                       packages.normalized_package_name,
                       packages.registry_url,
                       packages.repository_url,
                       packages.homepage_url,
                       packages.license,
                       packages.latest_version,
                       snapshots.downloads_30d,
                       snapshots.downloads_total,
                       snapshots.dependents_count,
                       snapshots.dependent_repositories_count,
                       MAX(COALESCE(user_stats.stargazers_count, organization_stats.stargazers_count)) AS repository_stars_count,
                       MAX(COALESCE(user_stats.monthly_stars_delta, organization_stats.monthly_stars_delta)) AS repository_stars_delta,
                       snapshots.latest_release_at,
                       COUNT(DISTINCT scans.id) AS linked_repository_count,
                       MIN(scans.full_name) AS repository_full_name,
                       MIN(scans.repository_kind) AS repository_kind,
                       MIN(scans.platform) AS repository_platform,
                       #{owner_login_sql('MIN(scans.full_name)')} AS repository_owner_login
                FROM registry_package_snapshots snapshots
                INNER JOIN registry_packages packages
                  ON packages.ecosystem = snapshots.ecosystem
                 AND packages.normalized_package_name = snapshots.normalized_package_name
                LEFT JOIN registry_package_links links
                  ON links.ecosystem = packages.ecosystem
                 AND links.normalized_package_name = packages.normalized_package_name
                 AND links.matched = 1
                LEFT JOIN package_manifests manifests ON manifests.id = links.manifest_id
                LEFT JOIN package_repository_scans scans ON scans.id = manifests.repository_scan_id
                LEFT JOIN repository_monthly_stats user_stats
                  ON scans.repository_kind = 'user'
                 AND user_stats.period_start = snapshots.period_start
                 AND user_stats.platform = scans.platform
                 AND user_stats.repository_github_id = scans.repository_source_id
                LEFT JOIN organization_repository_monthly_stats organization_stats
                  ON scans.repository_kind = 'organization'
                 AND organization_stats.period_start = snapshots.period_start
                 AND organization_stats.platform = scans.platform
                 AND organization_stats.repository_github_id = scans.repository_source_id
                WHERE snapshots.period_start = ?
                  AND snapshots.ecosystem = ?
                  AND packages.status = 'active'
                  #{repository_kind_filter(repository_kind)}
                GROUP BY snapshots.ecosystem, packages.normalized_package_name
              SQL
            end

            def ecosystem_cards_sql
              <<~SQL
                WITH linked_repositories AS (
                  SELECT DISTINCT snapshots.ecosystem,
                         scans.repository_kind,
                         scans.platform,
                         scans.repository_source_id,
                         scans.full_name,
                         COALESCE(user_stats.stargazers_count, organization_stats.stargazers_count, 0)
                           AS repository_stars_count
                  FROM registry_package_snapshots snapshots
                  INNER JOIN registry_packages packages
                    ON packages.ecosystem = snapshots.ecosystem
                   AND packages.normalized_package_name = snapshots.normalized_package_name
                  INNER JOIN registry_package_links links
                    ON links.ecosystem = packages.ecosystem
                   AND links.normalized_package_name = packages.normalized_package_name
                   AND links.matched = 1
                  INNER JOIN package_manifests manifests ON manifests.id = links.manifest_id
                  INNER JOIN package_repository_scans scans ON scans.id = manifests.repository_scan_id
                  LEFT JOIN repository_monthly_stats user_stats
                    ON scans.repository_kind = 'user'
                   AND user_stats.period_start = snapshots.period_start
                   AND user_stats.platform = scans.platform
                   AND user_stats.repository_github_id = scans.repository_source_id
                  LEFT JOIN organization_repository_monthly_stats organization_stats
                    ON scans.repository_kind = 'organization'
                   AND organization_stats.period_start = snapshots.period_start
                   AND organization_stats.platform = scans.platform
                   AND organization_stats.repository_github_id = scans.repository_source_id
                  WHERE snapshots.period_start = ?
                    AND packages.status = 'active'
                ),
                ecosystem_totals AS (
                  SELECT ecosystem,
                         COUNT(*) AS repository_count,
                         SUM(repository_stars_count) AS repository_stars_count
                  FROM linked_repositories
                  GROUP BY ecosystem
                )
                SELECT snapshots.ecosystem,
                       COUNT(DISTINCT snapshots.normalized_package_name) AS package_count,
                       COALESCE(ecosystem_totals.repository_count, 0) AS repository_count,
                       COALESCE(ecosystem_totals.repository_stars_count, 0) AS repository_stars_count
                FROM registry_package_snapshots snapshots
                INNER JOIN registry_packages packages
                  ON packages.ecosystem = snapshots.ecosystem
                 AND packages.normalized_package_name = snapshots.normalized_package_name
                LEFT JOIN ecosystem_totals ON ecosystem_totals.ecosystem = snapshots.ecosystem
                WHERE snapshots.period_start = ?
                  AND packages.status = 'active'
                GROUP BY snapshots.ecosystem
                ORDER BY repository_count DESC, snapshots.ecosystem COLLATE NOCASE ASC
              SQL
            end

            def package_profile_sql
              <<~SQL
                SELECT snapshots.ecosystem,
                       packages.package_name,
                       packages.normalized_package_name,
                       packages.registry_url,
                       packages.repository_url,
                       packages.homepage_url,
                       packages.license,
                       packages.latest_version,
                       snapshots.downloads_30d,
                       snapshots.downloads_total,
                       snapshots.dependents_count,
                       snapshots.dependent_repositories_count,
                       COALESCE(user_stats.stargazers_count, organization_stats.stargazers_count) AS repository_stars_count,
                       COALESCE(user_stats.monthly_stars_delta, organization_stats.monthly_stars_delta) AS repository_stars_delta,
                       snapshots.latest_release_at,
                       scans.full_name AS repository_full_name,
                       scans.repository_kind,
                       scans.platform AS repository_platform,
                       #{owner_login_sql('scans.full_name')} AS repository_owner_login
                FROM registry_package_snapshots snapshots
                INNER JOIN registry_packages packages
                  ON packages.ecosystem = snapshots.ecosystem
                 AND packages.normalized_package_name = snapshots.normalized_package_name
                LEFT JOIN registry_package_links links
                  ON links.ecosystem = packages.ecosystem
                 AND links.normalized_package_name = packages.normalized_package_name
                 AND links.matched = 1
                LEFT JOIN package_manifests manifests ON manifests.id = links.manifest_id
                LEFT JOIN package_repository_scans scans ON scans.id = manifests.repository_scan_id
                LEFT JOIN repository_monthly_stats user_stats
                  ON scans.repository_kind = 'user'
                 AND user_stats.period_start = snapshots.period_start
                 AND user_stats.platform = scans.platform
                 AND user_stats.repository_github_id = scans.repository_source_id
                LEFT JOIN organization_repository_monthly_stats organization_stats
                  ON scans.repository_kind = 'organization'
                 AND organization_stats.period_start = snapshots.period_start
                 AND organization_stats.platform = scans.platform
                 AND organization_stats.repository_github_id = scans.repository_source_id
                WHERE snapshots.period_start = ?
                  AND snapshots.ecosystem = ?
                  AND packages.normalized_package_name = ?
                  AND packages.status = 'active'
                ORDER BY scans.repository_kind ASC, scans.full_name COLLATE NOCASE ASC
              SQL
            end

            def package_profile_from(rows)
              first = rows.first
              first.except(:repository_full_name, :repository_kind, :repository_platform, :repository_owner_login)
                   .merge(
                     repository_stars_count: rows.filter_map { |row| row[:repository_stars_count] }.max,
                     repository_stars_delta: rows.filter_map { |row| row[:repository_stars_delta] }.max,
                     repositories: repository_links(rows)
                   )
            end

            def metric_filter_sql(metric)
              expression = metric_expression(metric)
              return "#{expression} > 0" if metric.to_s == 'repository_stars_delta'

              "#{expression} IS NOT NULL"
            end

            def sort_rankings(rows, metric, limit)
              rows.select { |row| metric_row?(row, metric) }
                  .sort_by { |row| ranking_sort_key(row, metric) }
                  .first(bounded_limit(limit))
            end

            def metric_row?(row, metric)
              value = row.fetch(metric.to_sym)
              return value.to_i.positive? if metric.to_s == 'repository_stars_delta'

              !value.nil?
            end

            def ranking_sort_key(row, metric)
              [-row.fetch(metric.to_sym).to_i, row.fetch(:package_name).downcase]
            end

            def metric_expression(metric)
              METRIC_EXPRESSIONS.fetch(metric)
            end

            def repository_links(rows)
              rows.filter_map do |row|
                next unless row[:repository_full_name]

                row.slice(:repository_full_name, :repository_kind, :repository_platform, :repository_owner_login)
              end
            end

            def owner_login_sql(full_name_expression)
              "substr(#{full_name_expression}, 1, instr(#{full_name_expression}, '/') - 1)"
            end

            def validate_metric!(metric)
              return if Domain::PackageRankingMetric.supported_key?(metric)

              raise ArgumentError, "Unsupported package ranking metric: #{metric}"
            end

            def validate_ecosystem_metric!(ecosystem, metric)
              return if Domain::PackageRankingMetric.supported_for_ecosystem?(ecosystem, metric)

              raise ArgumentError, "Unsupported package ranking metric for #{ecosystem}: #{metric}"
            end

            def validate_repository_kind!(repository_kind)
              return if repository_kind.nil? || %w[user organization].include?(repository_kind)

              raise ArgumentError, "Unsupported package repository kind: #{repository_kind}"
            end

            def repository_link_joins(repository_kind)
              return '' unless repository_kind

              <<~SQL
                INNER JOIN registry_package_links links
                  ON links.ecosystem = packages.ecosystem
                 AND links.normalized_package_name = packages.normalized_package_name
                 AND links.matched = 1
                INNER JOIN package_manifests manifests ON manifests.id = links.manifest_id
                INNER JOIN package_repository_scans scans ON scans.id = manifests.repository_scan_id
              SQL
            end

            def repository_kind_filter(repository_kind)
              repository_kind ? 'AND scans.repository_kind = ?' : ''
            end

            def bounded_limit(limit)
              limit.to_i.clamp(1, MAX_LIMIT)
            end
          end
        end
      end
    end
  end
end
