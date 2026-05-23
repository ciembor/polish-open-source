# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Domain
        class PackageManifest
          CONFIDENCE_LEVELS = %w[high medium low].freeze
          PARSE_STATUSES = %w[parsed partial private custom_registry unpublished failed].freeze

          attr_reader :confidence, :custom_registry, :ecosystem, :homepage_url, :license, :metadata,
                      :normalized_package_name, :package_name, :parse_status, :private_package, :repository_url

          def initialize(attributes)
            @ecosystem = attributes.fetch(:ecosystem)
            @package_name = blank_to_nil(attributes[:package_name])
            @normalized_package_name = normalize(attributes.fetch(:normalized_package_name, @package_name))
            @private_package = attributes.fetch(:private_package, false)
            @custom_registry = blank_to_nil(attributes[:custom_registry])
            @repository_url = blank_to_nil(attributes[:repository_url])
            @homepage_url = blank_to_nil(attributes[:homepage_url])
            @license = blank_to_nil(attributes[:license])
            @confidence = attributes.fetch(:confidence)
            @parse_status = attributes.fetch(:parse_status)
            @metadata = attributes.fetch(:metadata, {})
            validate!
          end

          def to_h
            {
              ecosystem: ecosystem,
              package_name: package_name,
              normalized_package_name: normalized_package_name,
              private_package: private_package,
              custom_registry: custom_registry,
              repository_url: repository_url,
              homepage_url: homepage_url,
              license: license,
              confidence: confidence,
              parse_status: parse_status,
              metadata: metadata
            }
          end

          private

          def validate!
            raise ArgumentError, "Unknown confidence level: #{confidence}" unless CONFIDENCE_LEVELS.include?(confidence)
            raise ArgumentError, "Unknown parse status: #{parse_status}" unless PARSE_STATUSES.include?(parse_status)
          end

          def normalize(value)
            blank_to_nil(value)&.downcase
          end

          def blank_to_nil(value)
            text = value&.to_s&.strip
            text.nil? || text.empty? ? nil : text
          end
        end
      end
    end
  end
end
