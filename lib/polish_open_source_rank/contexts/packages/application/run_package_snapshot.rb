# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Application
        class RunPackageSnapshot
          DEFAULT_LIMIT = 100

          def initialize(run_repository:, repository_queue:, manifest_scanner:, registry_packages:, registry_clients:)
            @run_repository = run_repository
            @repository_queue = repository_queue
            @manifest_scanner = manifest_scanner
            @registry_packages = registry_packages
            @registry_clients = registry_clients
          end

          def call(period, ecosystem: nil, limit: DEFAULT_LIMIT, refresh: false)
            run_id = run_repository.create(period, ecosystem: ecosystem, refresh: refresh)
            run_flow(period, ecosystem: ecosystem, limit: limit, refresh: refresh)
            run_repository.finish(run_id)
          rescue StandardError => e
            run_repository.fail(run_id, "#{e.class}: #{e.message}") if run_id
            raise
          end

          private

          attr_reader :manifest_scanner, :registry_clients, :registry_packages, :repository_queue, :run_repository

          def run_flow(period, ecosystem:, limit:, refresh:)
            repository_queue.enqueue(period, limit: limit)
            manifest_scanner.call(period, ecosystem: ecosystem, limit: limit, refresh: refresh)
            registry_packages.resolve_from_manifests(period, ecosystem: ecosystem, limit: limit)
            fetch_registry_snapshots(period, ecosystem: ecosystem, limit: limit, refresh: refresh)
          end

          def fetch_registry_snapshots(period, ecosystem:, limit:, refresh:)
            packages = registry_packages.packages_to_fetch(period, ecosystem: ecosystem, limit: limit, refresh: refresh)
            packages.each do |package_row|
              fetch_one(period, package_row)
            end
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
        end
      end
    end
  end
end
