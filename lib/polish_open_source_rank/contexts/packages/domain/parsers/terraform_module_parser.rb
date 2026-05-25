# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Domain
        module Parsers
          class TerraformModuleParser
            def parse(path:, content:)
              required_providers = content.scan(/\bsource\s*=\s*["']([^"']+)["']/).flatten
              PackageManifest.new(
                ecosystem: 'terraform',
                package_name: nil,
                confidence: 'medium',
                parse_status: 'partial',
                metadata: { path: path, required_providers: required_providers.uniq }
              )
            end
          end
        end
      end
    end
  end
end
