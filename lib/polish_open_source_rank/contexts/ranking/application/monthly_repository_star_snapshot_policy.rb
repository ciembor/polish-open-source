# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Ranking
      module Application
        # Computes monthly star metrics from stored monthly observations.
        class MonthlyRepositoryStarSnapshotPolicy
          def snapshot(_accepted_profile, repository, previous_stars:)
            {
              stars: repository.stars,
              monthly_stars_delta: monthly_stars_delta(repository, previous_stars)
            }
          end

          private

          def monthly_stars_delta(repository, previous_stars)
            return 0 unless previous_stars

            [repository.stars - previous_stars, 0].max
          end
        end
      end
    end
  end
end
