# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Ranking
      module Domain
        module SourceRecord
          def fetch(key, *fallback, &)
            to_h.fetch(key, *fallback, &)
          end

          def [](key)
            to_h[key]
          end

          def key?(key)
            to_h.key?(key)
          end

          def ==(other)
            other.is_a?(Hash) ? to_h == other : super
          end

          def include?(expected)
            return expected.all? { |key, value| self[key] == value } if expected.is_a?(Hash)

            to_h.include?(expected)
          end

          private

          def required_string(value, name)
            normalized = value.to_s
            raise ArgumentError, "#{name} is required" if normalized.empty?

            normalized
          end

          def required_source_id(value)
            raise ArgumentError, 'source_id is required' if value.nil?

            value
          end

          def optional_string(value)
            return if value.nil?

            value.to_s
          end

          def explicitly_true?(value)
            value == true
          end
        end
      end
    end
  end
end
