# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Domain
        module Parsers
          class ComposerJsonParser
            Helpers = StaticManifestParserHelpers
            TEMPLATE_PATH_SEGMENTS = %w[
              template templates fixture fixtures example examples demo demos sample samples
              test tests spec specs resource resources inspection inspections
            ].freeze

            def parse(path:, content:)
              data = JSON.parse(content)
              name = data['name']
              return partial('missing vendor/package name') unless valid_name?(name)

              PackageManifest.new(
                ecosystem: 'packagist',
                package_name: name,
                repository_url: data.dig('support', 'source'),
                homepage_url: data['homepage'],
                license: license(data['license']),
                confidence: 'high',
                parse_status: 'parsed',
                metadata: { path: path, issues_url: data.dig('support', 'issues') }.compact
              )
            rescue JSON::ParserError => e
              error_message = e.message
              return partial('empty composer.json') if content.to_s.strip.empty?

              if template_like_path?(path) || template_like_content?(content)
                return partial("non-literal composer.json: #{error_message}")
              end

              Helpers.failed('packagist', error_message)
            end

            private

            def partial(error)
              PackageManifest.new(
                ecosystem: 'packagist',
                confidence: 'low',
                parse_status: 'partial',
                metadata: { error: error }
              )
            end

            def valid_name?(name)
              name.to_s.match?(%r{\A[a-z0-9_.-]+/[a-z0-9_.-]+\z})
            end

            def license(value)
              value.is_a?(Array) ? value.join(', ') : value
            end

            def template_like_path?(path)
              normalized_segments = path.to_s.split('/').map { |segment| segment.downcase.gsub(/[^a-z0-9]+/, '_') }
              normalized_segments.any? { |segment| template_segment?(segment) }
            end

            def template_like_content?(content)
              content.to_s.match?(/{{|{%-|<%=?|<(?:warning|weak_warning)>/)
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
