# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Domain
        module Parsers
          class CranDescriptionParser
            def parse(path:, content:)
              name = field(content, 'Package')
              PackageManifest.new(
                ecosystem: 'cran',
                package_name: name,
                repository_url: field(content, 'URL'),
                homepage_url: field(content, 'URL'),
                license: field(content, 'License'),
                confidence: name ? 'high' : 'low',
                parse_status: name ? 'parsed' : 'failed',
                metadata: { path: path, version: field(content, 'Version') }
              )
            end

            private

            def field(content, name)
              content[/^#{Regexp.escape(name)}:\s*(.+)$/, 1]&.strip
            end
          end
        end
      end
    end
  end
end
