# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Infrastructure
        module SQLite
          class SQLitePackageRepositoryQueue
            include SQLiteRetryableErrors

            RETRYABLE_STATUSES = %w[pending failed].freeze
            REFRESHABLE_STATUSES = %w[pending failed scanned unavailable].freeze
            STALE_PROCESSING_SECONDS = 60 * 60

            def initialize(database, clock: -> { Time.now.utc })
              @database = database
              @clock = clock
            end

            def enqueue(period, limit:, include_forks: false)
              insert_scans(period_start(period), bounded_limit(limit), include_forks)
            end

            def pending(period, limit:, ecosystem: nil, refresh: false)
              validate_ecosystem!(ecosystem)
              retry_scan_ids = outdated_failed_manifest_scan_ids(ecosystem)
              retryable = Sequel.|({ status: statuses_for(refresh) }, { id: retry_scan_ids })
              scans = package_repository_scans
                      .where(period_start: period_start(period))
                      .where(retryable)
                      .order(Sequel.asc(:id))
                      .limit(bounded_limit(limit))
                      .all
              mark_outdated_manifest_retries(scans, retry_scan_ids)
            end

            def reset_stale_processing(period, older_than: STALE_PROCESSING_SECONDS)
              cutoff = (clock.call - older_than).iso8601
              package_repository_scans
                .where(period_start: period_start(period), status: 'processing')
                .where { updated_at < cutoff }
                .update(
                  status: 'failed',
                  error: 'processing scan was interrupted and will be retried',
                  updated_at: timestamp
                )
            end

            def mark_processing(scan_id)
              update(scan_id, status: 'processing', error: nil)
            end

            def mark_scanned(scan_id, tree_sha:, tree_truncated:, manifest_count:)
              update(
                scan_id,
                status: 'scanned',
                tree_sha: tree_sha,
                tree_truncated: tree_truncated ? 1 : 0,
                manifest_count: manifest_count.to_i,
                error: nil,
                checked_at: timestamp
              )
            end

            def mark_failed(scan_id, error)
              update(scan_id, status: 'failed', error: error)
            end

            def mark_unavailable(scan_id, error)
              update(scan_id, status: 'unavailable', error: error, checked_at: timestamp)
            end

            private

            attr_reader :clock, :database

            def statuses_for(refresh)
              refresh ? REFRESHABLE_STATUSES : RETRYABLE_STATUSES
            end

            def package_manifests
              database.dataset(:package_manifests)
            end

            def outdated_failed_manifest_scan_ids(ecosystem)
              dataset = package_manifests
                        .select(:repository_scan_id)
                        .distinct
                        .where(parse_status: 'failed')
                        .exclude(parser_version: SQLitePackageManifestRepository::PARSER_VERSION)
              dataset = dataset.where(ecosystem: ecosystem) if ecosystem
              dataset.map(:repository_scan_id)
            end

            def mark_outdated_manifest_retries(scans, retry_scan_ids)
              scans.each { |scan| scan[:retry_failed_manifests] = retry_scan_ids.include?(scan.fetch(:id)) ? 1 : 0 }
            end

            def validate_ecosystem!(ecosystem)
              return if Contexts::Packages::Domain::Ecosystem.supported?(ecosystem)

              raise ArgumentError, "Unsupported package ecosystem: #{ecosystem}"
            end

            def insert_scans(period_start, limit, include_forks)
              database.transaction do
                database.execute(insert_scans_sql(include_forks), [timestamp, period_start, period_start, limit])
              end
            end

            def insert_scans_sql(include_forks)
              <<~SQL
                INSERT OR IGNORE INTO package_repository_scans(
                  period_start, repository_kind, platform, repository_source_id, full_name, status, updated_at
                )
                SELECT period_start, repository_kind, platform, repository_source_id, full_name, 'pending', ?
                FROM (
                  #{user_repository_candidates_sql(include_forks)}
                  UNION ALL
                  #{organization_repository_candidates_sql(include_forks)}
                )
                ORDER BY priority ASC, stargazers_count DESC, monthly_stars_delta DESC,
                         repository_kind ASC, platform ASC, full_name COLLATE NOCASE ASC
                LIMIT ?
              SQL
            end

            def user_repository_candidates_sql(include_forks)
              <<~SQL
                SELECT stats.period_start,
                       'user' AS repository_kind,
                       repositories.platform,
                       repositories.github_id AS repository_source_id,
                       repositories.full_name,
                       stats.stargazers_count,
                       stats.monthly_stars_delta,
                       #{priority_sql('stats')}
                FROM repository_monthly_stats stats
                INNER JOIN repositories
                  ON repositories.platform = stats.platform
                 AND repositories.github_id = stats.repository_github_id
                WHERE stats.period_start = ?
                  AND stats.owner_country = 'Poland'
                  AND repositories.archived = 0
                  AND #{fork_condition(include_forks, 'repositories')}
                  AND (stats.stargazers_count >= 5 OR stats.monthly_stars_delta > 0)
              SQL
            end

            def organization_repository_candidates_sql(include_forks)
              <<~SQL
                SELECT stats.period_start,
                       'organization' AS repository_kind,
                       repositories.platform,
                       repositories.github_id AS repository_source_id,
                       repositories.full_name,
                       stats.stargazers_count,
                       stats.monthly_stars_delta,
                       #{priority_sql('stats')}
                FROM organization_repository_monthly_stats stats
                INNER JOIN organization_repositories repositories
                  ON repositories.platform = stats.platform
                 AND repositories.github_id = stats.repository_github_id
                WHERE stats.period_start = ?
                  AND stats.organization_country = 'Poland'
                  AND repositories.archived = 0
                  AND #{fork_condition(include_forks, 'repositories')}
                  AND (stats.stargazers_count >= 5 OR stats.monthly_stars_delta > 0)
              SQL
            end

            def priority_sql(table)
              <<~SQL
                CASE
                  WHEN #{table}.stargazers_count >= 100 THEN 0
                  WHEN #{table}.monthly_stars_delta > 0 THEN 1
                  WHEN #{table}.stargazers_count >= 5 THEN 2
                  ELSE 3
                END AS priority
              SQL
            end

            def fork_condition(include_forks, table)
              include_forks ? '1 = 1' : "#{table}.fork = 0"
            end

            def update(scan_id, attributes)
              translate_retryable_sqlite_failure do
                database.transaction do
                  package_repository_scans.where(id: scan_id).update(attributes.merge(updated_at: timestamp))
                end
              end
            end

            def package_repository_scans
              database.dataset(:package_repository_scans)
            end

            def period_start(period)
              period.respond_to?(:start_date) ? period.start_date.to_s : period.to_s
            end

            def bounded_limit(limit)
              limit.to_i.clamp(1, 10_000)
            end

            def timestamp
              clock.call.iso8601
            end
          end
        end
      end
    end
  end
end
