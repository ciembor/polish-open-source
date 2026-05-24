# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Infrastructure
        module Registries
          class HomebrewRegistryClient
            DEFAULT_BASE_URL = 'https://formulae.brew.sh'
            WEB_BASE_URL = 'https://formulae.brew.sh/formula'
            Helpers = RegistryClientHelpers

            def initialize(http_client: nil, requests_per_minute: 20, http: {}, execution: {})
              @http_client = http_client || RegistryHTTPClient.new(
                base_url: DEFAULT_BASE_URL,
                registry: 'homebrew',
                requests_per_minute: requests_per_minute,
                http: http,
                execution: execution
              )
            end

            def fetch(package_name)
              result = http_client.get_json("/api/formula/#{Helpers.escaped_segment(package_name)}.json")
              return Helpers.fetch_error(result) unless result.status == 'ok'

              registry_package = registry_package(result.body, package_name)
              snapshot = Domain::RegistryPackageSnapshot.new(
                ecosystem: 'homebrew',
                package_name: package_name,
                downloads_30d: install_count(result.body, '30d'),
                latest_version: registry_package.latest_version,
                metadata: analytics_metadata(result.body)
              )
              Domain::RegistryFetchResult.new(status: 'ok', package: registry_package, snapshot: snapshot)
            end

            private

            attr_reader :http_client

            def registry_package(body, package_name)
              Domain::RegistryPackage.new(
                ecosystem: 'homebrew',
                package_name: body['name'] || package_name,
                registry_url: "#{WEB_BASE_URL}/#{Helpers.escaped_segment(package_name)}",
                repository_url: stable_url(body),
                homepage_url: body['homepage'],
                license: Helpers.license(body['license']),
                latest_version: body.dig('versions', 'stable')
              )
            end

            def stable_url(body)
              body.dig('urls', 'stable', 'url')
            end

            def install_count(body, window)
              counts = body.dig('analytics', 'install', window)
              return unless counts.is_a?(Hash)

              counts.values.compact.sum
            end

            def analytics_metadata(body)
              {
                metric_source: 'homebrew_formula_install_analytics',
                installs_90d: install_count(body, '90d'),
                installs_365d: install_count(body, '365d'),
                generated_date: body['generated_date']
              }.compact
            end
          end
        end
      end
    end
  end
end
