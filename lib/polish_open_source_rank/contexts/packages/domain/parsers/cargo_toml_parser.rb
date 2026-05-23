# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Domain
        module Parsers
          class CargoTomlParser
            Helpers = StaticManifestParserHelpers

            def parse(path:, content:)
              package = Helpers.section(content, 'package')
              workspace = Helpers.section(content, 'workspace')
              name = Helpers.assignment(package, 'name')
              PackageManifest.new(
                ecosystem: 'crates',
                package_name: name,
                repository_url: Helpers.assignment(package, 'repository'),
                homepage_url: Helpers.assignment(package, 'homepage'),
                license: Helpers.assignment(package, 'license'),
                confidence: name ? 'high' : 'medium',
                parse_status: parse_status(package, name),
                metadata: { path: path, workspace_members: Helpers.array_assignment(workspace, 'members') }.compact
              )
            end

            private

            def parse_status(package, name)
              return 'unpublished' if Helpers.boolean_assignment(package, 'publish') == false

              name ? 'parsed' : 'partial'
            end
          end
        end
      end
    end
  end
end
