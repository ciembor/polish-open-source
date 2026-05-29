# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Application
        class RunPackageSnapshot
          DEFAULT_REPOSITORY_LIMIT = 5_000
          DEFAULT_SCAN_LIMIT = 5_000
          DEFAULT_MANIFEST_LIMIT = 10_000
          DEFAULT_REGISTRY_LIMIT = 10_000
          DEFAULT_LIMIT = DEFAULT_REPOSITORY_LIMIT
          Limits = Struct.new(:repository, :scan, :manifest, :registry, keyword_init: true)

          def initialize(run_repository:, repository_queue:, manifest_scanner:, registry_packages:, registry_clients:,
                         work_events: Operations::Application::JobWorkEventRecorder.new)
            @run_repository = run_repository
            @repository_queue = repository_queue
            @manifest_scanner = manifest_scanner
            @registry_packages = registry_packages
            @registry_clients = registry_clients
            @work_events = work_events
          end

          def call(period, ecosystem: nil, limit: nil, limits: nil, refresh: false)
            limits = snapshot_limits(limit: limit, limits: limits)
            run_id = run_repository.create(period, ecosystem: ecosystem, refresh: refresh)
            stats = run_flow(period, ecosystem: ecosystem, limits: limits, refresh: refresh)
            run_repository.finish(run_id)
            stats
          rescue StandardError => e
            run_repository.fail(run_id, "#{e.class}: #{e.message}") if run_id
            raise
          end

          private

          attr_reader :manifest_scanner, :registry_clients, :registry_packages, :repository_queue, :run_repository,
                      :work_events

          def run_flow(period, ecosystem:, limits:, refresh:)
            first_pass = execute_pass(period, ecosystem: ecosystem, limits: limits, refresh: refresh)
            return first_pass unless retryable_stage_failures?(first_pass)

            second_pass = execute_pass(period, ecosystem: ecosystem, limits: limits, refresh: refresh)
            first_pass.merge(
              scanned: first_pass.fetch(:scanned) + second_pass.fetch(:scanned),
              failed: second_pass.fetch(:failed),
              manifests: first_pass.fetch(:manifests) + second_pass.fetch(:manifests),
              registry_fetched: first_pass.fetch(:registry_fetched) + second_pass.fetch(:registry_fetched),
              registry_ok: first_pass.fetch(:registry_ok) + second_pass.fetch(:registry_ok),
              registry_not_found: first_pass.fetch(:registry_not_found) + second_pass.fetch(:registry_not_found),
              registry_rate_limited: second_pass.fetch(:registry_rate_limited),
              registry_failed: second_pass.fetch(:registry_failed),
              snapshots_written: first_pass.fetch(:snapshots_written) + second_pass.fetch(:snapshots_written),
              retry_passes: 1
            )
          end

          def fetch_registry_snapshots(period, ecosystem:, limit:, refresh:)
            packages = registry_packages.packages_to_fetch(period, ecosystem: ecosystem, limit: limit, refresh: refresh)
            stats = registry_stats
            packages.each do |package_row|
              result = record_registry_fetch_event(period, package_row) { fetch_one(period, package_row) }
              record_registry_stat(stats, result)
            end
            stats
          end

          def fetch_one(period, package_row)
            result = registry_client(package_row.fetch(:ecosystem)).fetch(package_row.fetch(:package_name))
          rescue StandardError => e
            result = Domain::RegistryFetchResult.new(status: 'failed', error: "#{e.class}: #{e.message}")
          ensure
            registry_packages.record_fetch_result(period, package_row, result) if result
          end

          def registry_client(ecosystem)
            registry_clients.fetch(ecosystem)
          end

          def registry_stats
            {
              registry_fetched: 0,
              registry_ok: 0,
              registry_not_found: 0,
              registry_rate_limited: 0,
              registry_failed: 0,
              snapshots_written: 0
            }
          end

          def record_registry_stat(stats, result)
            status_key = :"registry_#{result.status}"
            stats[:registry_fetched] += 1
            stats[status_key] += 1 if stats.key?(status_key)
            stats[:snapshots_written] += 1 if result.ok?
          end

          def record_registry_fetch_event(period, package_row, &)
            work_events.record_timed(
              period_start: period.start_date.to_s,
              job_kind: 'packages',
              stage: 'registry_snapshot',
              unit_kind: 'registry_snapshot',
              platform: nil,
              ecosystem: package_row.fetch(:ecosystem),
              subject_id: package_row.fetch(:normalized_package_name),
              subject_label: package_row.fetch(:package_name), &
            )
          end

          def snapshot_limits(limit:, limits:)
            return bounded_limits(limits) if limits
            return global_limits(limit) if limit

            Limits.new(
              repository: DEFAULT_REPOSITORY_LIMIT,
              scan: DEFAULT_SCAN_LIMIT,
              manifest: DEFAULT_MANIFEST_LIMIT,
              registry: DEFAULT_REGISTRY_LIMIT
            )
          end

          def global_limits(limit)
            value = limit.to_i
            Limits.new(repository: value, scan: value, manifest: value, registry: value)
          end

          def bounded_limits(limits)
            Limits.new(
              repository: limits.fetch(:repository),
              scan: limits.fetch(:scan),
              manifest: limits.fetch(:manifest),
              registry: limits.fetch(:registry)
            )
          end

          def execute_pass(period, ecosystem:, limits:, refresh:)
            stale_reset = repository_queue.reset_stale_processing(period)
            repository_queue.enqueue(period, limit: limits.repository)
            scan_stats = manifest_scanner.call(period, ecosystem: ecosystem, limit: limits.scan, refresh: refresh)
            registry_packages.resolve_from_manifests(period, ecosystem: ecosystem, limit: limits.manifest)
            registry_stats = fetch_registry_snapshots(period, ecosystem: ecosystem, limit: limits.registry,
                                                              refresh: refresh)
            scan_stats.merge(stale_scans_reset: stale_reset).merge(registry_stats)
          end

          def retryable_stage_failures?(stats)
            stats.fetch(:failed).positive? ||
              stats.fetch(:registry_failed).positive? ||
              stats.fetch(:registry_rate_limited).positive?
          end
        end
      end
    end
  end
end
