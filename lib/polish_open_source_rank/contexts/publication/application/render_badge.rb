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
            profile&.fetch(:badges, [])&.first
          end

          def repository(platform:, owner:, name:, period_start:)
            profile_read_model
              .repository_profile(platform, owner, name, period_start: period_start)
              &.fetch(:polish_repo_badge, nil)
          end

          private

          attr_reader :profile_read_model
        end
      end
    end
  end
end
