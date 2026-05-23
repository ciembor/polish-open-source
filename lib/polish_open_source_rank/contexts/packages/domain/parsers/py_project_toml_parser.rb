# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Domain
        module Parsers
          class PyProjectTomlParser
            Helpers = StaticManifestParserHelpers

            def parse(path:, content:)
              project = Helpers.section(content, 'project')
              poetry = Helpers.section(content, 'tool.poetry')
              name = Helpers.assignment(project, 'name') || Helpers.assignment(poetry, 'name')
              PackageManifest.new(
                ecosystem: 'pypi',
                package_name: name,
                license: Helpers.assignment(project, 'license'),
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
