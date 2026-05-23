# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Domain
        module Parsers
          class NpmPackageJsonParser
            Helpers = StaticManifestParserHelpers

            PUBLIC_REGISTRY = 'https://registry.npmjs.org/'

            def parse(path:, content:)
              data = JSON.parse(content)
              name = data['name']
              return Helpers.failed('npm', 'missing name') unless name

              PackageManifest.new(
                ecosystem: 'npm',
                package_name: name,
                private_package: data['private'] == true,
                custom_registry: custom_registry(data),
                repository_url: repository_url(data['repository']),
                homepage_url: data['homepage'],
                license: data['license'],
                confidence: 'high',
                parse_status: parse_status(data),
                metadata: { path: path, workspaces: data['workspaces'] }.compact
              )
            rescue JSON::ParserError => e
              Helpers.failed('npm', e.message)
            end

            private

            def custom_registry(data)
              registry = data.dig('publishConfig', 'registry')
              registry && registry != PUBLIC_REGISTRY ? registry : nil
            end

            def parse_status(data)
              return 'private' if data['private'] == true
              return 'custom_registry' if custom_registry(data)

              'parsed'
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
