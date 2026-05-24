# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Infrastructure
        module SQLite
          class SQLiteRegistryPackageRepository
            FETCHABLE_PARSE_STATUSES = %w[parsed partial].freeze
            REGISTRY_URLS = {
              'npm' => 'https://www.npmjs.com/package/%s',
              'rubygems' => 'https://rubygems.org/gems/%s',
              'crates' => 'https://crates.io/crates/%s',
              'pypi' => 'https://pypi.org/project/%s/',
              'hex' => 'https://hex.pm/packages/%s',
              'packagist' => 'https://packagist.org/packages/%s',
              'go' => 'https://pkg.go.dev/%s'
            }.freeze

            def initialize(database, clock: -> { Time.now.utc })
              @database = database
              @clock = clock
            end

            def resolve_from_manifests(period, ecosystem: nil, limit: 100)
              database.transaction do
                fetchable_manifests(period, ecosystem: ecosystem, limit: limit).each do |manifest|
                  upsert_pending_package(manifest)
                  link_manifest(manifest)
                end
              end
            end

            def packages_to_fetch(period, ecosystem: nil, limit: 100, refresh: false)
              dataset = registry_packages.where(Sequel[:registry_packages][:ecosystem] => ecosystems_for(ecosystem))
              dataset = dataset.exclude(Sequel[:registry_packages][:status] => 'not_found') unless refresh
              dataset = without_snapshot(dataset, period) unless refresh
              dataset
                .order(
                  Sequel.asc(Sequel[:registry_packages][:ecosystem]),
                  Sequel.asc(Sequel[:registry_packages][:normalized_package_name])
                )
                .limit(bounded_limit(limit))
                .all
            end

            def record_fetch_result(period, package_row, result)
              database.transaction do
                result.ok? ? record_success(period, result) : record_failure(package_row, result)
              end
            end

            private

            attr_reader :clock, :database

            def fetchable_manifests(period, ecosystem:, limit:)
              dataset = package_manifests
                        .join(:package_repository_scans, id: :repository_scan_id)
                        .where(
                          Sequel[:package_repository_scans][:period_start] => period_start(period),
                          Sequel[:package_manifests][:parse_status] => FETCHABLE_PARSE_STATUSES
                        )
                        .exclude(Sequel[:package_manifests][:normalized_package_name] => nil)
              dataset = dataset.where(Sequel[:package_manifests][:ecosystem] => ecosystem) if ecosystem
              dataset
                .select_all(:package_manifests)
                .order(Sequel.asc(Sequel[:package_manifests][:id]))
                .limit(bounded_limit(limit))
                .all
            end

            def upsert_pending_package(manifest)
              registry_packages.insert_conflict(
                target: %i[ecosystem normalized_package_name],
                update: {
                  package_name: Sequel[:excluded][:package_name],
                  repository_url: Sequel[:excluded][:repository_url],
                  homepage_url: Sequel[:excluded][:homepage_url],
                  license: Sequel[:excluded][:license],
                  updated_at: timestamp
                }
              ).insert(
                ecosystem: manifest.fetch(:ecosystem),
                package_name: manifest.fetch(:package_name),
                normalized_package_name: manifest.fetch(:normalized_package_name),
                registry_url: registry_url(manifest.fetch(:ecosystem), manifest.fetch(:package_name)),
                repository_url: manifest[:repository_url],
                homepage_url: manifest[:homepage_url],
                license: manifest[:license],
                status: 'pending',
                updated_at: timestamp
              )
            end

            def link_manifest(manifest)
              registry_package_links.insert_conflict(
                target: %i[manifest_id ecosystem normalized_package_name],
                update: { match_confidence: Sequel[:excluded][:match_confidence], checked_at: timestamp }
              ).insert(
                manifest_id: manifest.fetch(:id),
                ecosystem: manifest.fetch(:ecosystem),
                normalized_package_name: manifest.fetch(:normalized_package_name),
                match_confidence: manifest.fetch(:confidence),
                matched: 1,
                checked_at: timestamp
              )
            end

            def record_success(period, result)
              package = result.package
              registry_packages.insert_conflict(
                target: %i[ecosystem normalized_package_name],
                update: registry_package_update(package)
              ).insert(registry_package_insert(package))
              registry_package_snapshots.insert_conflict(
                target: %i[ecosystem normalized_package_name period_start],
                update: snapshot_update(result.snapshot)
              ).insert(snapshot_insert(period, result.snapshot))
            end

            def record_failure(package_row, result)
              registry_packages
                .where(
                  ecosystem: package_row.fetch(:ecosystem),
                  normalized_package_name: package_row.fetch(:normalized_package_name)
                )
                .update(
                  status: result.status,
                  error: result.error,
                  checked_at: timestamp,
                  updated_at: timestamp
                )
            end

            def registry_package_insert(package)
              package.to_h.slice(
                :ecosystem, :package_name, :normalized_package_name, :registry_url, :repository_url,
                :homepage_url, :license, :latest_version, :status, :error
              ).merge(checked_at: timestamp, updated_at: timestamp)
            end

            def registry_package_update(package)
              registry_package_insert(package).slice(
                :package_name, :registry_url, :repository_url, :homepage_url, :license, :latest_version,
                :status, :error, :checked_at, :updated_at
              )
            end

            def snapshot_insert(period, snapshot)
              snapshot.to_h.slice(
                :ecosystem, :normalized_package_name, :downloads_total, :downloads_30d, :downloads_7d,
                :dependents_count, :dependent_repositories_count, :latest_version, :latest_release_at
              ).merge(period_start: period_start(period), metadata_json: JSON.generate(snapshot.metadata),
                      observed_at: timestamp)
            end

            def snapshot_update(snapshot)
              snapshot.to_h.slice(
                :downloads_total, :downloads_30d, :downloads_7d, :dependents_count,
                :dependent_repositories_count, :latest_version, :latest_release_at
              ).merge(metadata_json: JSON.generate(snapshot.metadata), observed_at: timestamp)
            end

            def without_snapshot(dataset, period)
              dataset
                .left_join(
                  :registry_package_snapshots,
                  ecosystem: Sequel[:registry_packages][:ecosystem],
                  normalized_package_name: Sequel[:registry_packages][:normalized_package_name],
                  period_start: period_start(period)
                )
                .where(Sequel[:registry_package_snapshots][:ecosystem] => nil)
                .select_all(:registry_packages)
            end

            def registry_url(ecosystem, package_name)
              format(REGISTRY_URLS.fetch(ecosystem), package_name)
            end

            def ecosystems_for(ecosystem)
              ecosystem || Contexts::Packages::Domain::Ecosystem.snapshot_supported
            end

            def package_manifests
              database.dataset(:package_manifests)
            end

            def registry_packages
              database.dataset(:registry_packages)
            end

            def registry_package_links
              database.dataset(:registry_package_links)
            end

            def registry_package_snapshots
              database.dataset(:registry_package_snapshots)
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
