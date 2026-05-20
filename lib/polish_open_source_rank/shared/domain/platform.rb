# frozen_string_literal: true

module PolishOpenSourceRank
  module Shared
    module Domain
      class Platform
        SUPPORTED = %w[github gitlab codeberg].freeze

        def self.coerce(value)
          value.is_a?(self) ? value : new(value)
        end

        attr_reader :key

        def initialize(value)
          @key = value.to_s
          raise ArgumentError, "Unsupported platform: #{value.inspect}" unless SUPPORTED.include?(@key)
        end

        def to_s
          key
        end

        def ==(other)
          other.respond_to?(:to_s) && key == other.to_s
        end
      end
    end
  end
end
