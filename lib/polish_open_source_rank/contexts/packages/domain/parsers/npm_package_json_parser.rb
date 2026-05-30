# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Domain
        module Parsers
          class NpmPackageJsonParser
            Helpers = StaticManifestParserHelpers

            PUBLIC_REGISTRY = 'https://registry.npmjs.org/'
            TEMPLATE_PATH_SEGMENTS = %w[
              template templates fixture fixtures example examples demo demos sample samples
              scaffold scaffolding starter starters seed seeds dev
            ].freeze

            def parse(path:, content:)
              data = JSON.parse(content)
              name = data['name']
              return partial('missing name') unless name

              parsed_manifest(path, data, name)
            rescue JSON::ParserError => e
              error_message = e.message
              if template_like_path?(path) || template_like_content?(content)
                return partial("non-literal package.json: #{error_message}")
              end

              Helpers.failed('npm', error_message)
            end

            private

            def partial(error)
              PackageManifest.new(
                ecosystem: 'npm',
                confidence: 'low',
                parse_status: 'partial',
                metadata: { error: error }
              )
            end

            def parsed_manifest(path, data, name)
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
            end

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

            def template_like_path?(path)
              normalized_segments = path.to_s.split('/').map { |segment| segment.downcase.gsub(/[^a-z0-9]+/, '_') }
              normalized_segments.any? { |segment| template_segment?(segment) }
            end

            def template_like_content?(content)
              content.to_s.match?(/{{|{%-|<%=?|{package_name|cookiecutter\./)
            end

            def template_segment?(segment)
              TEMPLATE_PATH_SEGMENTS.any? { |keyword| segment.include?(keyword) }
            end
          end
        end
      end
    end
  end
end
