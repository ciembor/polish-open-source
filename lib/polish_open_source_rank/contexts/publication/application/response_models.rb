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

        class ProfilePage < HashResponse
          def repositories
            fetch(:repositories)
          end

          def badges
            fetch(:badges, [])
          end
        end

        class RepositoryPage < HashResponse
          def badge
            self[:polish_repo_badge]
          end
        end

        class BadgeView < HashResponse
        end
      end
    end
  end
end
