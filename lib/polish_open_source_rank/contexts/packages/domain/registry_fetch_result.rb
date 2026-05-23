# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Domain
        class RegistryFetchResult
          STATUSES = %w[ok not_found rate_limited failed].freeze

          attr_reader :error, :package, :retry_after, :snapshot, :status

          def initialize(status:, package: nil, snapshot: nil, error: nil, retry_after: nil)
            raise ArgumentError, "Unsupported registry fetch status: #{status}" unless STATUSES.include?(status)

            @status = status
            @package = package
            @snapshot = snapshot
            @error = error
            @retry_after = retry_after
          end

          def ok?
            status == 'ok'
          end
        end
      end
    end
  end
end
