# frozen_string_literal: true

module PolishOpenSourceRank
  module Shared
    module Domain
      # Represents a source account login where path separators would change route meaning.
      class Login
        def initialize(value)
          @value = value.to_s
          raise ArgumentError, 'login is required' if @value.empty?
          raise ArgumentError, "Invalid login: #{value.inspect}" if @value.include?('/')
        end

        def to_s
          value
        end

        private

        attr_reader :value
      end
    end
  end
end
