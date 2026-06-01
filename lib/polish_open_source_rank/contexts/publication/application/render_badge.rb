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
            return unless period_start

            request = ProfileRequest.new(platform: platform, login: login, period_start: period_start)
            profile = profile_read_model.user_profile(
              request.platform_key,
              request.login_key,
              period_start: request.period_start_key
            )
            badge = profile&.fetch(:profile_badge, nil)
            badge && BadgeView.new(badge)
          end

          def repository(platform:, owner:, name:, period_start:)
            return unless period_start

            request = RepositoryProfileRequest.new(platform: platform, owner: owner, name: name,
                                                   period_start: period_start)
            profile = profile_read_model.repository_profile(
              request.platform_key,
              request.full_name_key,
              period_start: request.period_start_key
            )
            badge = profile&.fetch(:polish_repo_badge, nil)
            badge && BadgeView.new(badge)
          end

          def organization(platform:, login:, period_start:)
            return unless period_start

            request = ProfileRequest.new(platform: platform, login: login, period_start: period_start)
            profile = profile_read_model.organization_profile(
              request.platform_key,
              request.login_key,
              period_start: request.period_start_key
            )
            badge = profile&.fetch(:profile_badge, nil)
            badge && BadgeView.new(badge)
          end

          private

          attr_reader :profile_read_model
        end
      end
    end
  end
end
