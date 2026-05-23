# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Domain
        module Parsers
          class SetupCfgParser
            Helpers = StaticManifestParserHelpers

            def parse(path:, content:)
              metadata = Helpers.section(content, 'metadata')
              name = Helpers.assignment(metadata, 'name')
              PackageManifest.new(
                ecosystem: 'pypi',
                package_name: name,
                homepage_url: Helpers.assignment(metadata, 'url'),
                license: Helpers.assignment(metadata, 'license'),
                confidence: name ? 'high' : 'low',
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
