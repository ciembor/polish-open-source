# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Ranking
      module Application
        # Selects the repository star source for monthly snapshot metrics.
        class MonthlyRepositoryStarSnapshotPolicy
          def snapshot(accepted_profile, repository)
            {
              stars: repository.stars,
              monthly_stars_delta: monthly_stars_delta(accepted_profile, repository)
            }
          end

          private

          def monthly_stars_delta(accepted_profile, repository)
            return 0 if repository.zero_stars?

            accepted_profile.source.repository_stars_delta(repository, accepted_profile.period)
          end
        end
      end
    end
  end
end
