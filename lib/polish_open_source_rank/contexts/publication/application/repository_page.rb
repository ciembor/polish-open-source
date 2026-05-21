# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Publication
      module Application
        class RepositoryPage < HashResponse
          def badge
            self[:polish_repo_badge]
          end
        end
      end
    end
  end
end
