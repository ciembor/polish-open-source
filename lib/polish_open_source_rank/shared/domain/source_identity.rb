# frozen_string_literal: true

module PolishOpenSourceRank
  module Shared
    module Domain
      class SourceIdentity
        attr_reader :platform, :source_id

        def initialize(platform:, source_id:)
          raise ArgumentError, 'source_id is required' if source_id.nil?

          @platform = Platform.coerce(platform)
          @source_id = source_id
        end

        def platform_key
          platform.to_s
        end
      end
    end
  end
end
