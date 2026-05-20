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
        end
      end
    end
  end
end
