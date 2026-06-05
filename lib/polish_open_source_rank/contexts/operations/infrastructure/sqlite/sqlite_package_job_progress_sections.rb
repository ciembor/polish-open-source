# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Operations
      module Infrastructure
        module SQLite
          class SQLitePackageJobProgressSections
            REPOSITORY_SCAN_SQL = <<~SQL
              SELECT repository_kind,
                     COUNT(*) AS total,
                     SUM(CASE WHEN status = 'scanned' THEN 1 ELSE 0 END) AS done,
                     SUM(CASE WHEN status IN ('pending', 'processing') THEN 1 ELSE 0 END) AS pending,
                     SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) AS failed
              FROM package_repository_scans
              WHERE period_start = ?
              GROUP BY repository_kind
              ORDER BY repository_kind
            SQL
            MANIFEST_SQL = <<~SQL
              SELECT package_manifests.ecosystem,
                     COUNT(*) AS total,
                     SUM(CASE WHEN package_manifests.parse_status = 'failed' THEN 0 ELSE 1 END) AS done,
                     SUM(CASE WHEN package_manifests.parse_status = 'failed' THEN 1 ELSE 0 END) AS failed,
                     SUM(CASE WHEN package_manifests.parse_status IN ('private', 'unpublished', 'custom_registry')
                              THEN 1 ELSE 0 END) AS skipped
              FROM package_manifests
              INNER JOIN package_repository_scans
                ON package_repository_scans.id = package_manifests.repository_scan_id
              WHERE package_repository_scans.period_start = ?
              GROUP BY package_manifests.ecosystem
              ORDER BY package_manifests.ecosystem
            SQL
            REGISTRY_PACKAGE_SQL = <<~SQL
              SELECT ecosystem,
                     COUNT(*) AS total,
                     COUNT(*) AS done,
                     0 AS pending,
                     0 AS failed,
                     0 AS skipped
              FROM registry_packages
              GROUP BY ecosystem
              ORDER BY ecosystem
            SQL
            REGISTRY_SNAPSHOT_SQL = <<~SQL
              SELECT registry_packages.ecosystem,
                     COUNT(*) AS total,
                     COUNT(registry_package_snapshots.normalized_package_name) AS done,
                     SUM(CASE WHEN registry_packages.status = 'active' THEN 1 ELSE 0 END) AS active,
                     SUM(CASE WHEN registry_packages.status = 'pending' THEN 1 ELSE 0 END) AS pending,
                     SUM(CASE WHEN registry_packages.status = 'not_found' THEN 1 ELSE 0 END) AS not_found,
                     SUM(CASE WHEN registry_packages.status = 'rate_limited' THEN 1 ELSE 0 END) AS rate_limited,
                     SUM(CASE WHEN registry_packages.status = 'failed' THEN 1 ELSE 0 END) AS failed
              FROM registry_packages
              LEFT JOIN registry_package_snapshots
                ON registry_package_snapshots.ecosystem = registry_packages.ecosystem
               AND registry_package_snapshots.normalized_package_name = registry_packages.normalized_package_name
               AND registry_package_snapshots.period_start = ?
              GROUP BY registry_packages.ecosystem
              ORDER BY registry_packages.ecosystem
            SQL

            def initialize(database:, section_builder:)
              @database = database
              @section_builder = section_builder
            end

            def call(period_start, now)
              repository_scan_sections(period_start, now) +
                manifest_sections(period_start, now) +
                registry_package_sections(period_start, now) +
                registry_snapshot_sections(period_start, now)
            end

            private

            attr_reader :database, :section_builder

            def repository_scan_sections(period_start, now)
              fetch_all(REPOSITORY_SCAN_SQL, [period_start]).map do |row|
                section(repository_scan_attributes(row, period_start, now))
              end
            end

            def manifest_sections(period_start, now)
              fetch_all(MANIFEST_SQL, [period_start]).map do |row|
                section(manifest_attributes(row, period_start, now))
              end
            end

            def registry_package_sections(period_start, now)
              fetch_all(REGISTRY_PACKAGE_SQL).map do |row|
                section(registry_package_attributes(row, period_start, now))
              end
            end

            def registry_snapshot_sections(period_start, now)
              fetch_all(REGISTRY_SNAPSHOT_SQL, [period_start]).map do |row|
                section(registry_snapshot_attributes(row, period_start, now))
              end
            end

            def repository_scan_attributes(row, period_start, now)
              {
                label: "package repository scans / #{row.fetch(:repository_kind)}",
                period_start: period_start,
                job_kind: 'packages',
                stage: 'repository_scan',
                unit_kind: 'package_repository_scan',
                total: row.fetch(:total).to_i,
                done: row.fetch(:done).to_i,
                pending: row.fetch(:pending).to_i,
                failed: row.fetch(:failed).to_i,
                skipped: 0,
                status_detail: nil,
                now: now
              }
            end

            def manifest_attributes(row, period_start, now)
              {
                label: "package manifests / #{row.fetch(:ecosystem)}",
                period_start: period_start,
                job_kind: 'packages',
                stage: 'manifest_parse',
                unit_kind: 'package_manifest',
                ecosystem: row.fetch(:ecosystem),
                total: row.fetch(:total).to_i,
                done: row.fetch(:done).to_i,
                pending: 0,
                failed: row.fetch(:failed).to_i,
                skipped: row.fetch(:skipped).to_i,
                status_detail: nil,
                now: now
              }
            end

            def registry_package_attributes(row, period_start, now)
              {
                label: "registry packages / #{row.fetch(:ecosystem)}",
                period_start: period_start,
                job_kind: 'packages',
                stage: 'registry_resolve',
                unit_kind: 'registry_package',
                ecosystem: row.fetch(:ecosystem),
                total: row.fetch(:total).to_i,
                done: row.fetch(:done).to_i,
                pending: row.fetch(:pending).to_i,
                failed: row.fetch(:failed).to_i,
                skipped: row.fetch(:skipped).to_i,
                status_detail: nil,
                now: now
              }
            end

            def registry_snapshot_attributes(row, period_start, now)
              {
                label: "registry snapshots / #{row.fetch(:ecosystem)}",
                period_start: period_start,
                job_kind: 'packages',
                stage: 'registry_snapshot',
                unit_kind: 'registry_snapshot',
                ecosystem: row.fetch(:ecosystem),
                total: row.fetch(:total).to_i,
                done: row.fetch(:done).to_i,
                pending: row.fetch(:pending).to_i,
                failed: row.fetch(:failed).to_i + row.fetch(:rate_limited).to_i,
                skipped: row.fetch(:not_found).to_i,
                status_detail: registry_snapshot_detail(row),
                now: now
              }
            end

            def registry_snapshot_detail(row)
              {
                active: row.fetch(:active),
                pending: row.fetch(:pending),
                not_found: row.fetch(:not_found),
                rate_limited: row.fetch(:rate_limited),
                failed: row.fetch(:failed)
              }.map { |status, count| "#{status}=#{count.to_i}" }.join(', ')
            end

            def section(attributes)
              section_builder.call(attributes)
            end

            def fetch_all(sql, params = [])
              database.fetch_all(sql, params)
            end
          end
        end
      end
    end
  end
end
