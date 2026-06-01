# frozen_string_literal: true

module PolishOpenSourceRank
  module Shared
    module Infrastructure
      module SQLite
        # Whitelists SQL fragments that must be interpolated because SQLite cannot bind identifiers.
        class SqlExpressionMap
          def initialize(expressions, name:)
            @expressions = expressions.transform_keys(&:to_s).freeze
            @name = name
          end

          def fetch(key)
            expressions.fetch(key.to_s) do
              raise ArgumentError, "Unsupported #{name}: #{key}"
            end
          end

          private

          attr_reader :expressions, :name
        end
      end
    end
  end
end
