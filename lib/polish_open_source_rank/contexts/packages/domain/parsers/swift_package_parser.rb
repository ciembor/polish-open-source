# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Domain
        module Parsers
          class SwiftPackageParser
            def parse(path:, content:)
              name = content[/Package\s*\(\s*name:\s*["']([^"']+)["']/, 1]
              platforms = content.scan(/\.(macOS|iOS|tvOS|watchOS|visionOS)\s*\(/).flatten.uniq
              PackageManifest.new(
                ecosystem: 'swiftpm',
                package_name: name,
                confidence: name ? 'medium' : 'low',
                parse_status: name ? 'parsed' : 'partial',
                metadata: { path: path, platforms: platforms }
              )
            end
          end
        end
      end
    end
  end
end
