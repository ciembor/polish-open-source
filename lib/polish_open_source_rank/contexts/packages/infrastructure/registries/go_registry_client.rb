# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Infrastructure
        module Registries
          class GoRegistryClient
            DEFAULT_BASE_URL = 'https://proxy.golang.org'
            WEB_BASE_URL = 'https://pkg.go.dev'
            Helpers = RegistryClientHelpers

            def initialize(http_client: nil, requests_per_minute: 20, http: {}, execution: {})
              @http_client = http_client || RegistryHTTPClient.new(
                base_url: DEFAULT_BASE_URL,
                registry: 'go',
                requests_per_minute: requests_per_minute,
                http: http,
                execution: execution
              )
            end

            def fetch(package_name)
              result = http_client.get_json("/#{package_name}/@latest")
              return Helpers.fetch_error(result) unless result.status == 'ok'

              package = Domain::RegistryPackage.new(
                ecosystem: 'go',
                package_name: package_name,
                registry_url: "#{WEB_BASE_URL}/#{package_name}",
                repository_url: "#{WEB_BASE_URL}/#{package_name}",
                latest_version: result.body['Version']
              )
              snapshot = Domain::RegistryPackageSnapshot.new(
                ecosystem: 'go',
                package_name: package_name,
                latest_version: package.latest_version,
                latest_release_at: result.body['Time']
              )
              Domain::RegistryFetchResult.new(status: 'ok', package: package, snapshot: snapshot)
            end

            private

            attr_reader :http_client
          end
        end
      end
    end
  end
end
