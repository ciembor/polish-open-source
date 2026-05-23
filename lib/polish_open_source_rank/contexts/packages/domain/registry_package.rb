# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Domain
        class RegistryPackage
          STATUSES = %w[active not_found rate_limited failed].freeze

          attr_reader :ecosystem, :error, :homepage_url, :latest_version, :license, :metadata,
                      :normalized_package_name, :package_name, :registry_url, :repository_url, :status

          def initialize(**attributes)
            status = attributes.fetch(:status, 'active')
            raise ArgumentError, "Unsupported registry package status: #{status}" unless STATUSES.include?(status)

            @ecosystem = attributes.fetch(:ecosystem)
            @package_name = attributes.fetch(:package_name)
            @normalized_package_name = package_name.to_s.downcase
            @registry_url = attributes.fetch(:registry_url)
            @repository_url = attributes[:repository_url]
            @homepage_url = attributes[:homepage_url]
            @license = attributes[:license]
            @latest_version = attributes[:latest_version]
            @status = status
            @error = attributes[:error]
            @metadata = attributes.fetch(:metadata, {})
          end

          def to_h
            {
              ecosystem: ecosystem,
              package_name: package_name,
              normalized_package_name: normalized_package_name,
              registry_url: registry_url,
              repository_url: repository_url,
              homepage_url: homepage_url,
              license: license,
              latest_version: latest_version,
              status: status,
              error: error,
              metadata: metadata
            }
          end
        end
      end
    end
  end
end
