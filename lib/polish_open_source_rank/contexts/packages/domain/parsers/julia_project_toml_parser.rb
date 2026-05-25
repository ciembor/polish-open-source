# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Domain
        module Parsers
          class JuliaProjectTomlParser
            Helpers = StaticManifestParserHelpers

            def parse(path:, content:)
              name = Helpers.assignment(content, 'name')
              PackageManifest.new(
                ecosystem: 'julia',
                package_name: name,
                repository_url: Helpers.assignment(content, 'repo'),
                homepage_url: Helpers.assignment(content, 'repo'),
                confidence: name ? 'high' : 'low',
                parse_status: name ? 'parsed' : 'partial',
                metadata: { path: path, version: Helpers.assignment(content, 'version') }
              )
            end
          end
        end
      end
    end
  end
end
