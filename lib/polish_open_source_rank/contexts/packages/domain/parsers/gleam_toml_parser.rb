# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Domain
        module Parsers
          class GleamTomlParser
            Helpers = StaticManifestParserHelpers

            def parse(path:, content:)
              name = Helpers.assignment(content, 'name')
              PackageManifest.new(
                ecosystem: 'hex',
                package_name: name,
                confidence: name ? 'high' : 'medium',
                parse_status: name ? 'parsed' : 'partial',
                metadata: { path: path }
              )
            end
          end
        end
      end
    end
  end
end
