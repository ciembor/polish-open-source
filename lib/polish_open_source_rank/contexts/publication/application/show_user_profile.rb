# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Publication
      module Application
        class ShowUserProfile
          def initialize(profile_read_model:)
            @profile_read_model = profile_read_model
          end

          def call(platform:, login:, period_start:)
            request = ProfileRequest.new(platform: platform, login: login, period_start: period_start)
            profile = profile_read_model.user_profile(
              request.platform_key,
              request.login_key,
              period_start: request.period_start_key
            )
            profile && ProfilePage.new(profile)
          end

          private

          attr_reader :profile_read_model
        end
      end
    end
  end
end
