# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Ranking
      module Application
        # Selects the repository star source for monthly snapshot metrics.
        class MonthlyRepositoryStarSnapshotPolicy
          def snapshot(accepted_profile, repository, previous_stars_role:)
            {
              stars: repository.stars,
              monthly_stars_delta: monthly_stars_delta(accepted_profile, repository, previous_stars_role)
            }
          end

          private

          def monthly_stars_delta(accepted_profile, repository, previous_stars_role)
            return 0 if repository.zero_stars?

            previous_stars = previous_stars(accepted_profile, repository, previous_stars_role)
            if previous_stars && accepted_profile.use_snapshot_star_diff?
              return [repository.stars - previous_stars.to_i, 0].max
            end

            accepted_profile.source.repository_stars_delta(repository, accepted_profile.period)
          end

          def previous_stars(accepted_profile, repository, previous_stars_role)
            accepted_profile.previous_stars.public_send(
              previous_stars_role,
              accepted_profile.period,
              accepted_profile.source_platform,
              repository
            )
          end
        end
      end
    end
  end
end
