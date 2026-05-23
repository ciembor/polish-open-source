# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Infrastructure
        module Registries
          class NpmRegistryClient
            DEFAULT_BASE_URL = 'https://registry.npmjs.org'
            WEB_BASE_URL = 'https://www.npmjs.com/package'
            Helpers = RegistryClientHelpers

            def initialize(http_client: nil, requests_per_minute: 30, http: {}, execution: {})
              @http_client = http_client || RegistryHTTPClient.new(
                base_url: DEFAULT_BASE_URL,
                registry: 'npm',
                requests_per_minute: requests_per_minute,
                http: http,
                execution: execution
              )
            end

            def fetch(package_name)
              metadata = http_client.get_json("/#{Helpers.escaped_segment(package_name)}")
              return Helpers.fetch_error(metadata) unless metadata.status == 'ok'

              week = downloads(package_name, 'last-week')
              return with_package_error(metadata.body, week) unless week.status == 'ok'

              month = downloads(package_name, 'last-month')
              return with_package_error(metadata.body, month) unless month.status == 'ok'

              success(package_name, metadata.body, week.body, month.body)
            end

            private

            attr_reader :http_client

            def downloads(package_name, range)
              http_client.get_json("/-/api/v1/downloads/point/#{range}/#{Helpers.escaped_segment(package_name)}")
            end

            def success(package_name, metadata, week, month)
              package = registry_package(package_name, metadata)
              snapshot = Domain::RegistryPackageSnapshot.new(
                ecosystem: 'npm',
                package_name: package_name,
                downloads_7d: week['downloads'],
                downloads_30d: month['downloads'],
                latest_version: package.latest_version
              )
              Domain::RegistryFetchResult.new(status: 'ok', package: package, snapshot: snapshot)
            end

            def registry_package(package_name, metadata)
              Domain::RegistryPackage.new(
                ecosystem: 'npm',
                package_name: package_name,
                registry_url: "#{WEB_BASE_URL}/#{package_name}",
                repository_url: repository_url(metadata['repository']),
                homepage_url: metadata['homepage'],
                license: Helpers.license(metadata['license']),
                latest_version: metadata.dig('dist-tags', 'latest')
              )
            end

            def with_package_error(metadata, result)
              Domain::RegistryFetchResult.new(
                status: result.status,
                package: registry_package(metadata['name'], metadata),
                error: result.error,
                retry_after: result.retry_after
              )
            end

            def repository_url(value)
              return value if value.is_a?(String)

              value['url'] if value.is_a?(Hash)
            end
          end
        end
      end
    end
  end
end
