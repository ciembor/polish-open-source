# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Infrastructure
        module SQLite
          class SQLitePackageRankingReadModel
            DEFAULT_LIMIT = 100
            MAX_LIMIT = 100

            def initialize(database)
              @database = database
            end

            def ecosystems(period_start:)
              database.fetch_all(<<~SQL, [period_start]).map { |row| row.fetch(:ecosystem) }
                SELECT DISTINCT snapshots.ecosystem
                FROM registry_package_snapshots snapshots
                INNER JOIN registry_packages packages
                  ON packages.ecosystem = snapshots.ecosystem
                 AND packages.normalized_package_name = snapshots.normalized_package_name
                WHERE snapshots.period_start = ?
                  AND packages.status = 'active'
                ORDER BY snapshots.ecosystem ASC
              SQL
            end

            def rankings(ecosystem:, period_start:, limit: DEFAULT_LIMIT)
              Domain::PackageRankingMetric.keys(ecosystem: ecosystem).to_h do |metric|
                [metric.to_sym, ranked_packages(ecosystem: ecosystem, period_start: period_start, metric: metric,
                                                limit: limit)]
              end
            end

            def ranked_packages(ecosystem:, period_start:, metric:, scope: 'poland', limit: DEFAULT_LIMIT)
              validate_metric!(metric)
              validate_ecosystem_metric!(ecosystem, metric)
              return [] unless scope == 'poland'

              database.fetch_all(ranked_packages_sql(metric, limit), [period_start, ecosystem])
            end

            def package_profile(ecosystem:, package_name:, period_start:)
              rows = database.fetch_all(package_profile_sql, [period_start, ecosystem, package_name.to_s.downcase])
              return if rows.empty?

              package_profile_from(rows)
            end

            private

            attr_reader :database

            def ranked_packages_sql(metric, limit)
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
                GROUP BY snapshots.ecosystem, packages.normalized_package_name
                HAVING #{metric_filter_sql(metric)}
                ORDER BY #{metric_expression(metric)} DESC, packages.package_name COLLATE NOCASE ASC
                LIMIT #{bounded_limit(limit)}
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

            def metric_expression(metric)
              case metric.to_s
              when 'repository_stars_count'
                'MAX(COALESCE(user_stats.stargazers_count, organization_stats.stargazers_count))'
              when 'repository_stars_delta'
                'MAX(COALESCE(user_stats.monthly_stars_delta, organization_stats.monthly_stars_delta))'
              else
                "snapshots.#{metric}"
              end
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

            def bounded_limit(limit)
              limit.to_i.clamp(1, MAX_LIMIT)
            end
          end
        end
      end
    end
  end
end
