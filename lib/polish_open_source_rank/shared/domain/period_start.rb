# frozen_string_literal: true

module PolishOpenSourceRank
  module Shared
    module Domain
      # Normalizes period boundaries passed into use cases to the persisted month start date.
      class PeriodStart
        def initialize(value)
          @date = Date.iso8601(value.to_s)
        rescue Date::Error
          raise ArgumentError, "Invalid period_start: #{value.inspect}"
        end

        def to_s
          date.to_s
        end

        private

        attr_reader :date
      end
    end
  end
end
