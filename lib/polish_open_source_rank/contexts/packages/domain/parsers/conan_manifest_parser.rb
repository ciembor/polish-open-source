# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Domain
        module Parsers
          class ConanManifestParser
            Helpers = StaticManifestParserHelpers

            def parse(path:, content:)
              name = Helpers.assignment(content, 'name') || conanfile_txt_name(content)
              PackageManifest.new(
                ecosystem: 'conan',
                package_name: name,
                homepage_url: Helpers.assignment(content, 'homepage') || Helpers.assignment(content, 'url'),
                license: Helpers.assignment(content, 'license'),
                confidence: name ? 'medium' : 'low',
                parse_status: name ? 'parsed' : 'partial',
                metadata: { path: path, version: Helpers.assignment(content, 'version') }
              )
            end

            private

            def conanfile_txt_name(content)
              content[/^\s*name\s*=\s*([^\s#]+)/, 1]
            end
          end
        end
      end
    end
  end
end
