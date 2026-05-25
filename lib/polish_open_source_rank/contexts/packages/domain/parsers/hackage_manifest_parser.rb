# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Domain
        module Parsers
          class HackageManifestParser
            def parse(path:, content:)
              name = scalar(content, 'name')
              PackageManifest.new(
                ecosystem: 'hackage',
                package_name: name,
                repository_url: source_repository(content),
                homepage_url: scalar(content, 'homepage'),
                license: scalar(content, 'license'),
                confidence: name ? 'high' : 'low',
                parse_status: name ? 'parsed' : 'partial',
                metadata: { path: path, version: scalar(content, 'version') }
              )
            end

            private

            def scalar(content, key)
              content[/^\s*#{Regexp.escape(key)}:\s*['"]?([^'"\n#]+)['"]?/, 1]&.strip
            end

            def source_repository(content)
              content[/^\s*location:\s*['"]?([^'"\n#]+)['"]?/, 1]&.strip
            end
          end
        end
      end
    end
  end
end
