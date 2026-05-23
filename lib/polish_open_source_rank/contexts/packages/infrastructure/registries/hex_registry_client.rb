# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Infrastructure
        module Registries
          class HexRegistryClient
            DEFAULT_BASE_URL = 'https://hex.pm'
            Helpers = RegistryClientHelpers

            def initialize(http_client: nil, requests_per_minute: 20, http: {}, execution: {})
              @http_client = http_client || RegistryHTTPClient.new(
                base_url: DEFAULT_BASE_URL,
                registry: 'hex',
                requests_per_minute: requests_per_minute,
                http: http,
                execution: execution
              )
            end

            def fetch(package_name)
              result = http_client.get_json("/api/packages/#{Helpers.escaped_segment(package_name)}")
              return Helpers.fetch_error(result) unless result.status == 'ok'

              package = registry_package(package_name, result.body)
              snapshot = Domain::RegistryPackageSnapshot.new(
                ecosystem: 'hex',
                package_name: package_name,
                downloads_total: result.body.dig('downloads', 'all'),
                latest_version: package.latest_version
              )
              Domain::RegistryFetchResult.new(status: 'ok', package: package, snapshot: snapshot)
            end

            private

            attr_reader :http_client

            def registry_package(package_name, body)
              meta = body['meta'] || {}
              Domain::RegistryPackage.new(
                ecosystem: 'hex',
                package_name: package_name,
                registry_url: "#{DEFAULT_BASE_URL}/packages/#{package_name}",
                repository_url: meta['source_url'],
                homepage_url: meta['homepage_url'],
                latest_version: body['latest_stable_version'] || body['latest_version']
              )
            end
          end
        end
      end
    end
  end
end
