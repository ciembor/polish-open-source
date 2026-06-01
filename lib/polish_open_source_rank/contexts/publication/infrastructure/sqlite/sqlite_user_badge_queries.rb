# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Publication
      module Infrastructure
        module SQLite
          # Builds profile badges from persisted ranking data.
          module SQLiteUserBadgeQueries
            private

            def user_badges(profile:, language_badge:)
              badge_policy.user_badges(profile: profile, language_badge: language_badge)
            end

            def effective_public_period(record, requested_period)
              record[:period_start] || requested_period
            end

            def user_badges_for(_user, _public_period, profile)
              user_badges(
                profile: profile,
                language_badge: nil
              )
            end
          end
        end
      end
    end
  end
end
