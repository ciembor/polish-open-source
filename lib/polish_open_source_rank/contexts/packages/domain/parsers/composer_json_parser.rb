# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Domain
        module Parsers
          class ComposerJsonParser
            Helpers = StaticManifestParserHelpers

            def parse(path:, content:)
              data = JSON.parse(content)
              name = data['name']
              return Helpers.failed('packagist', 'missing vendor/package name') unless valid_name?(name)

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
              Helpers.failed('packagist', e.message)
            end

            private

            def valid_name?(name)
              name.to_s.match?(%r{\A[^/]+/[^/]+\z})
            end

            def license(value)
              value.is_a?(Array) ? value.join(', ') : value
            end
          end
        end
      end
    end
  end
end
