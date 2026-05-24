# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Infrastructure
        module Registries
          class MavenCentralRegistryClient
            DEFAULT_BASE_URL = 'https://search.maven.org'
            WEB_BASE_URL = 'https://central.sonatype.com/artifact'

            def initialize(http_client: nil, requests_per_minute: 20, http: {}, execution: {})
              @http_client = http_client || RegistryHTTPClient.new(
                base_url: DEFAULT_BASE_URL,
                registry: 'maven',
                requests_per_minute: requests_per_minute,
                http: http,
                execution: execution
              )
            end

            def fetch(package_name)
              group_id, artifact_id = package_name.to_s.split(':', 2)
              return Domain::RegistryFetchResult.new(status: 'not_found') unless group_id && artifact_id

              result = http_client.get_json(
                '/solrsearch/select',
                params: { q: %(g:"#{group_id}" AND a:"#{artifact_id}"), rows: 1, wt: 'json' }
              )
              return RegistryClientHelpers.fetch_error(result) unless result.status == 'ok'

              data = exact_match(result.body, group_id, artifact_id)
              return Domain::RegistryFetchResult.new(status: 'not_found') unless data

              package = registry_package(data, group_id, artifact_id)
              snapshot = Domain::RegistryPackageSnapshot.new(
                ecosystem: 'maven',
                package_name: package_name,
                latest_version: package.latest_version,
                metadata: { metric_source: 'maven_central_downloads_unavailable' }
              )
              Domain::RegistryFetchResult.new(status: 'ok', package: package, snapshot: snapshot)
            end

            private

            attr_reader :http_client

            def exact_match(body, group_id, artifact_id)
              body.dig('response', 'docs').to_a.find do |candidate|
                candidate['g'] == group_id && candidate['a'] == artifact_id
              end
            end

            def registry_package(data, group_id, artifact_id)
              Domain::RegistryPackage.new(
                ecosystem: 'maven',
                package_name: "#{group_id}:#{artifact_id}",
                registry_url: "#{WEB_BASE_URL}/#{group_id}/#{artifact_id}",
                latest_version: data['latestVersion']
              )
            end
          end
        end
      end
    end
  end
end
