# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Infrastructure
        module Registries
          class NuGetRegistryClient
            SearchResource = Struct.new(:base_url, :path, keyword_init: true)

            DEFAULT_BASE_URL = 'https://api.nuget.org'
            WEB_BASE_URL = 'https://www.nuget.org/packages'
            Helpers = RegistryClientHelpers

            def initialize(http_client: nil, requests_per_minute: 20, http: {}, execution: {})
              @requests_per_minute = requests_per_minute
              @http = http
              @execution = execution
              @http_client = http_client || RegistryHTTPClient.new(
                base_url: DEFAULT_BASE_URL,
                registry: 'nuget',
                requests_per_minute: requests_per_minute,
                http: http,
                execution: execution
              )
            end

            def fetch(package_name)
              resource = search_resource
              return Helpers.fetch_error(resource) unless resource.is_a?(SearchResource)

              result = search_http_client(resource).get_json(
                resource.path,
                params: { q: "packageid:#{package_name}", prerelease: false, semVerLevel: '2.0.0', take: 5 }
              )
              return Helpers.fetch_error(result) unless result.status == 'ok'

              data = exact_match(result.body, package_name)
              return Domain::RegistryFetchResult.new(status: 'not_found') unless data

              registry_package = registry_package(data, package_name)
              snapshot = Domain::RegistryPackageSnapshot.new(
                ecosystem: 'nuget',
                package_name: package_name,
                downloads_total: data['totalDownloads'],
                latest_version: registry_package.latest_version
              )
              Domain::RegistryFetchResult.new(status: 'ok', package: registry_package, snapshot: snapshot)
            end

            private

            attr_reader :execution, :http, :http_client, :requests_per_minute

            def search_resource
              result = http_client.get_json('/v3/index.json')
              return result unless result.status == 'ok'

              resource = result.body.fetch('resources', []).find do |candidate|
                candidate['@type'].to_s.start_with?('SearchQueryService')
              end
              unless resource
                return Domain::RegistryFetchResult.new(status: 'failed', error: 'missing SearchQueryService')
              end

              search_resource_from(resource.fetch('@id'))
            end

            def search_resource_from(url)
              uri = URI(url)
              base_url = "#{uri.scheme}://#{uri.host}"
              base_url = "#{base_url}:#{uri.port}" unless [80, 443].include?(uri.port)
              SearchResource.new(base_url: base_url, path: uri.path)
            end

            def search_http_client(resource)
              RegistryHTTPClient.new(
                base_url: resource.base_url,
                registry: 'nuget-search',
                requests_per_minute: requests_per_minute,
                http: http,
                execution: execution
              )
            end

            def exact_match(body, package_name)
              body.fetch('data', []).find { |candidate| candidate['id'].to_s.downcase == package_name.downcase }
            end

            def registry_package(data, package_name)
              Domain::RegistryPackage.new(
                ecosystem: 'nuget',
                package_name: data['id'] || package_name,
                registry_url: "#{WEB_BASE_URL}/#{Helpers.escaped_segment(data['id'] || package_name)}",
                repository_url: data['projectUrl'],
                homepage_url: data['projectUrl'],
                license: data['licenseExpression'] || data['licenseUrl'],
                latest_version: data['version']
              )
            end
          end
        end
      end
    end
  end
end
