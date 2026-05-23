# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Infrastructure
        module Registries
          class RubyGemsRegistryClient
            DEFAULT_BASE_URL = 'https://rubygems.org'
            Helpers = RegistryClientHelpers

            def initialize(http_client: nil, requests_per_minute: 20, http: {}, execution: {})
              @http_client = http_client || RegistryHTTPClient.new(
                base_url: DEFAULT_BASE_URL,
                registry: 'rubygems',
                requests_per_minute: requests_per_minute,
                http: http,
                execution: execution
              )
            end

            def fetch(package_name)
              result = http_client.get_json("/api/v1/gems/#{Helpers.escaped_segment(package_name)}.json")
              return Helpers.fetch_error(result) unless result.status == 'ok'

              package = registry_package(package_name, result.body)
              snapshot = Domain::RegistryPackageSnapshot.new(
                ecosystem: 'rubygems',
                package_name: package_name,
                downloads_total: result.body['downloads'],
                dependents_count: result.body['reverse_dependencies_count'],
                latest_version: package.latest_version
              )
              Domain::RegistryFetchResult.new(status: 'ok', package: package, snapshot: snapshot)
            end

            private

            attr_reader :http_client

            def registry_package(package_name, body)
              Domain::RegistryPackage.new(
                ecosystem: 'rubygems',
                package_name: package_name,
                registry_url: body['project_uri'] || "#{DEFAULT_BASE_URL}/gems/#{package_name}",
                repository_url: Helpers.first_present(body, 'source_code_uri', 'bug_tracker_uri'),
                homepage_url: body['homepage_uri'],
                license: Helpers.license(body['licenses']),
                latest_version: body['version']
              )
            end
          end
        end
      end
    end
  end
end
