# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Domain
        class RegistryPackageSnapshot
          attr_reader :dependent_repositories_count, :dependents_count, :downloads_7d, :downloads_30d,
                      :downloads_total, :ecosystem, :latest_release_at, :latest_version, :metadata,
                      :normalized_package_name, :package_name

          def initialize(**attributes)
            @ecosystem = attributes.fetch(:ecosystem)
            @package_name = attributes.fetch(:package_name)
            @normalized_package_name = package_name.to_s.downcase
            @downloads_total = attributes[:downloads_total]
            @downloads_30d = attributes[:downloads_30d]
            @downloads_7d = attributes[:downloads_7d]
            @dependents_count = attributes[:dependents_count]
            @dependent_repositories_count = attributes[:dependent_repositories_count]
            @latest_version = attributes[:latest_version]
            @latest_release_at = attributes[:latest_release_at]
            @metadata = attributes.fetch(:metadata, {})
          end

          def to_h
            {
              ecosystem: ecosystem,
              package_name: package_name,
              normalized_package_name: normalized_package_name,
              downloads_total: downloads_total,
              downloads_30d: downloads_30d,
              downloads_7d: downloads_7d,
              dependents_count: dependents_count,
              dependent_repositories_count: dependent_repositories_count,
              latest_version: latest_version,
              latest_release_at: latest_release_at,
              metadata: metadata
            }
          end
        end
      end
    end
  end
end
