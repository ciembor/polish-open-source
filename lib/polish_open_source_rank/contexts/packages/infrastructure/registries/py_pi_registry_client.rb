# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Infrastructure
        module Registries
          class PyPIRegistryClient
            DEFAULT_BASE_URL = 'https://pypi.org'
            Helpers = RegistryClientHelpers

            def initialize(http_client: nil, requests_per_minute: 20, http: {}, execution: {})
              @http_client = http_client || RegistryHTTPClient.new(
                base_url: DEFAULT_BASE_URL,
                registry: 'pypi',
                requests_per_minute: requests_per_minute,
                http: http,
                execution: execution
              )
            end

            def fetch(package_name)
              result = http_client.get_json("/pypi/#{Helpers.escaped_segment(package_name)}/json")
              return Helpers.fetch_error(result) unless result.status == 'ok'

              info = result.body.fetch('info')
              package = registry_package(package_name, info)
              snapshot = Domain::RegistryPackageSnapshot.new(
                ecosystem: 'pypi',
                package_name: package_name,
                latest_version: package.latest_version,
                metadata: { downloads_source: 'unavailable_without_bigquery' }
              )
              Domain::RegistryFetchResult.new(status: 'ok', package: package, snapshot: snapshot)
            end

            private

            attr_reader :http_client

            def registry_package(package_name, info)
              Domain::RegistryPackage.new(
                ecosystem: 'pypi',
                package_name: package_name,
                registry_url: info['package_url'] || "#{DEFAULT_BASE_URL}/project/#{package_name}/",
                repository_url: project_url(info['project_urls']),
                homepage_url: info['home_page'],
                license: info['license'],
                latest_version: info['version']
              )
            end

            def project_url(project_urls)
              return unless project_urls.is_a?(Hash)

              Helpers.first_present(project_urls, 'Source', 'Source Code', 'Repository', 'Homepage')
            end
          end
        end
      end
    end
  end
end
