# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Domain
        module Parsers
          class VcpkgJsonParser
            def parse(path:, content:)
              body = JSON.parse(content)
              PackageManifest.new(
                ecosystem: 'vcpkg',
                package_name: body['name'],
                homepage_url: body['homepage'],
                license: body['license'],
                confidence: body['name'] ? 'high' : 'low',
                parse_status: body['name'] ? 'parsed' : 'partial',
                metadata: { path: path, version: body['version'] || body['version-string'] }
              )
            rescue JSON::ParserError => e
              StaticManifestParserHelpers.failed('vcpkg', e.message)
            end
          end
        end
      end
    end
  end
end
