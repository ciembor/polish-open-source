# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Publication
      module Application
        class HashResponse
          def initialize(attributes)
            @attributes = attributes
          end

          def [](key)
            attributes[key]
          end

          def fetch(key, *, &)
            attributes.fetch(key, *, &)
          end

          def to_h
            attributes.dup
          end

          private

          attr_reader :attributes
        end
      end
    end
  end
end
