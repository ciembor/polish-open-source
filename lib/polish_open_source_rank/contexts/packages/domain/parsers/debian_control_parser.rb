# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Domain
        module Parsers
          class DebianControlParser
            def parse(path:, content:)
              source = field(content, 'Source')
              PackageManifest.new(
                ecosystem: 'apt',
                package_name: source,
                homepage_url: field(content, 'Homepage'),
                license: nil,
                confidence: source ? 'high' : 'low',
                parse_status: source ? 'parsed' : 'failed',
                metadata: {
                  path: path,
                  maintainer: field(content, 'Maintainer'),
                  standards_version: field(content, 'Standards-Version')
                }
              )
            end

            private

            def field(content, name)
              content[/^#{Regexp.escape(name)}:\s*(.+)$/i, 1]&.strip
            end
          end
        end
      end
    end
  end
end
