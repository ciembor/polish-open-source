# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Infrastructure
        module Registries
          class PackagistRegistryClient
            DEFAULT_BASE_URL = 'https://packagist.org'
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
              return invalid_package_result(package_name) unless valid_name?(package_name)

              result = http_client.get_json("/packages/#{package_name}.json")
              return Helpers.fetch_error(result) unless result.status == 'ok'

              package_data = result.body.fetch('package', {})
              version = latest_version(package_data)
              registry_package = registry_package(package_name, package_data, version)
              snapshot = Domain::RegistryPackageSnapshot.new(
                ecosystem: 'packagist',
                package_name: package_name,
                downloads_total: package_data.dig('downloads', 'total'),
                downloads_30d: package_data.dig('downloads', 'monthly'),
                downloads_7d: package_data.dig('downloads', 'daily'),
                latest_version: registry_package.latest_version
              )
              Domain::RegistryFetchResult.new(status: 'ok', package: registry_package, snapshot: snapshot)
            end

            private

            attr_reader :http_client

            def invalid_package_result(package_name)
              package = Domain::RegistryPackage.new(
                ecosystem: 'packagist',
                package_name: package_name,
                registry_url: "#{WEB_BASE_URL}/#{package_name}",
                status: 'not_found',
                error: 'invalid package name'
              )
              Domain::RegistryFetchResult.new(status: 'not_found', package: package, error: package.error)
            end

            def valid_name?(package_name)
              package_name.to_s.match?(%r{\A[a-z0-9_.-]+/[a-z0-9_.-]+\z})
            end

            def latest_version(package_data)
              versions = package_data.fetch('versions', [])
              records = versions.is_a?(Hash) ? versions.values : versions
              records.first || {}
            end

            def registry_package(package_name, package_data, version)
              Domain::RegistryPackage.new(
                ecosystem: 'packagist',
                package_name: package_name,
                registry_url: "#{WEB_BASE_URL}/#{package_name}",
                repository_url: package_data['repository'] || version.dig('source', 'url'),
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
