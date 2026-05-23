# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Infrastructure
        module Registries
          class PackagistRegistryClient
            DEFAULT_BASE_URL = 'https://repo.packagist.org'
            WEB_BASE_URL = 'https://packagist.org/packages'
            Helpers = RegistryClientHelpers

            def initialize(http_client: nil, requests_per_minute: 20, http: {}, execution: {})
              @http_client = http_client || RegistryHTTPClient.new(
                base_url: DEFAULT_BASE_URL,
                registry: 'packagist',
                requests_per_minute: requests_per_minute,
                http: http,
                execution: execution
              )
            end

            def fetch(package_name)
              result = http_client.get_json("/p2/#{package_name}.json")
              return Helpers.fetch_error(result) unless result.status == 'ok'

              version = versions(result.body, package_name).first || {}
              package = registry_package(package_name, version)
              snapshot = Domain::RegistryPackageSnapshot.new(
                ecosystem: 'packagist',
                package_name: package_name,
                latest_version: package.latest_version
              )
              Domain::RegistryFetchResult.new(status: 'ok', package: package, snapshot: snapshot)
            end

            private

            attr_reader :http_client

            def versions(body, package_name)
              body.fetch('packages', {}).fetch(package_name, [])
            end

            def registry_package(package_name, version)
              Domain::RegistryPackage.new(
                ecosystem: 'packagist',
                package_name: package_name,
                registry_url: "#{WEB_BASE_URL}/#{package_name}",
                repository_url: version.dig('source', 'url'),
                homepage_url: version['homepage'],
                license: Helpers.license(version['license']),
                latest_version: version['version']
              )
            end
          end
        end
      end
    end
  end
end
