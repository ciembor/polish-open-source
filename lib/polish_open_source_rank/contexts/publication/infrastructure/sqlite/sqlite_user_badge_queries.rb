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

            def user_badges_for(user, public_period, profile)
              user_badges(
                profile: profile,
                language_badge: user_language_badge_read_model.top_badge(
                  platform: user.fetch(:platform),
                  user_id: user.fetch(:github_id),
                  period_start: public_period
                )
              )
            end
          end
        end
      end
    end
  end
end
