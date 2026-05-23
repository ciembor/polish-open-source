# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Domain
        module Parsers
          class GoModParser
            def parse(path:, content:)
              name = content[/^\s*module\s+(\S+)/, 1]
              PackageManifest.new(
                ecosystem: 'go',
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
