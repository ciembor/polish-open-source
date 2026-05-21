# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Publication
      module Application
        class RenderBadge
          def initialize(profile_read_model:)
            @profile_read_model = profile_read_model
          end

          def user(platform:, login:, period_start:)
            profile = profile_read_model.user_profile(platform, login, period_start: period_start)
            badge = profile&.fetch(:badges, [])&.first
            badge && BadgeView.new(badge)
          end

          def repository(platform:, owner:, name:, period_start:)
            badge = profile_read_model
                    .repository_profile(platform, owner, name, period_start: period_start)
                    &.fetch(:polish_repo_badge, nil)
            badge && BadgeView.new(badge)
          end

          private

          attr_reader :profile_read_model
        end
      end
    end
  end
end
