# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Domain
        module RepositoryBackedPackageIdentity
          ECOSYSTEMS = %w[terraform].freeze

          module_function

          def apply(manifest, scan_context)
            return manifest unless ECOSYSTEMS.include?(manifest.ecosystem)
            return manifest if manifest.package_name

            full_name = scan_context.fetch(:full_name)
            PackageManifest.new(
              manifest.to_h.merge(
                package_name: full_name,
                normalized_package_name: full_name.downcase,
                repository_url: repository_url(scan_context),
                confidence: 'medium',
                parse_status: 'parsed',
                metadata: manifest.metadata.merge(identity_source: 'repository_full_name')
              )
            )
          end

          def repository_url(scan_context)
            return unless scan_context.fetch(:platform) == 'github'

            "https://github.com/#{scan_context.fetch(:full_name)}"
          end
        end
      end
    end
  end
end
