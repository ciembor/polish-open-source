# frozen_string_literal: true

module PolishOpenSourceRank
  module Shared
    module Domain
      SourceIdentity = Struct.new(:platform, :source_id, keyword_init: true) do
        def initialize(platform:, source_id:)
          super(platform: Platform.coerce(platform), source_id: source_id)
          raise ArgumentError, 'source_id is required' if source_id.nil?
        end

        def platform_key
          platform.to_s
        end
      end
    end
  end
end
