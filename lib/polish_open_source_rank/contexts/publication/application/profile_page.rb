# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Publication
      module Application
        class ProfilePage < HashResponse
          def repositories
            fetch(:repositories)
          end

          def badges
            fetch(:badges, [])
          end
        end
      end
    end
  end
end
