# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Publication
      module Application
        class ShowOrganizationProfile
          def initialize(profile_read_model:)
            @profile_read_model = profile_read_model
          end

          def call(platform:, login:, period_start:)
            profile = profile_read_model.organization_profile(platform, login, period_start: period_start)
            profile && ProfilePage.new(profile)
          end

          private

          attr_reader :profile_read_model
        end
      end
    end
  end
end
