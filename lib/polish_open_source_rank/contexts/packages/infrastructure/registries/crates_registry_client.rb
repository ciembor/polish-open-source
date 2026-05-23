# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Infrastructure
        module Registries
          class CratesRegistryClient
            DEFAULT_BASE_URL = 'https://crates.io'
            Helpers = RegistryClientHelpers

            def initialize(http_client: nil, requests_per_minute: 10, http: {}, execution: {})
              @http_client = http_client || RegistryHTTPClient.new(
                base_url: DEFAULT_BASE_URL,
                registry: 'crates',
                requests_per_minute: requests_per_minute,
                http: http,
                execution: execution
              )
            end

            def fetch(package_name)
              result = http_client.get_json("/api/v1/crates/#{Helpers.escaped_segment(package_name)}")
              return Helpers.fetch_error(result) unless result.status == 'ok'

              crate = result.body.fetch('crate')
              package = registry_package(package_name, crate)
              snapshot = Domain::RegistryPackageSnapshot.new(
                ecosystem: 'crates',
                package_name: package_name,
                downloads_total: crate['downloads'],
                downloads_30d: crate['recent_downloads'],
                latest_version: package.latest_version
              )
              Domain::RegistryFetchResult.new(status: 'ok', package: package, snapshot: snapshot)
            end

            private

            attr_reader :http_client

            def registry_package(package_name, crate)
              Domain::RegistryPackage.new(
                ecosystem: 'crates',
                package_name: package_name,
                registry_url: "#{DEFAULT_BASE_URL}/crates/#{package_name}",
                repository_url: crate['repository'],
                homepage_url: crate['homepage'],
                license: crate['license'],
                latest_version: crate['max_version']
              )
            end
          end
        end
      end
    end
  end
end
