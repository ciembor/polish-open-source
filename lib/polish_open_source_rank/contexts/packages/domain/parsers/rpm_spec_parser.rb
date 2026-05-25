# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Domain
        module Parsers
          class RpmSpecParser
            def parse(path:, content:)
              name = tag(content, 'Name')
              PackageManifest.new(
                ecosystem: 'rpm',
                package_name: name,
                repository_url: source_url(content),
                homepage_url: tag(content, 'URL'),
                license: tag(content, 'License'),
                confidence: name ? 'medium' : 'low',
                parse_status: name ? 'parsed' : 'failed',
                metadata: { path: path, version: tag(content, 'Version') }
              )
            end

            private

            def tag(content, name)
              content[/^#{Regexp.escape(name)}:\s*(.+)$/i, 1]&.strip
            end

            def source_url(content)
              content[%r{^Source\d*:\s*(https?://\S+)}i, 1]&.strip
            end
          end
        end
      end
    end
  end
end
