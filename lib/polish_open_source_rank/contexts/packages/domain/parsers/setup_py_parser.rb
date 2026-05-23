# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Domain
        module Parsers
          class SetupPyParser
            Helpers = StaticManifestParserHelpers

            def parse(path:, content:)
              name = Helpers.python_setup_name(content)
              PackageManifest.new(
                ecosystem: 'pypi',
                package_name: name,
                confidence: name ? 'medium' : 'low',
                parse_status: 'partial',
                metadata: { path: path }
              )
            end
          end
        end
      end
    end
  end
end
