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
            profile_read_model.user_profile(platform, login, period_start: period_start)
          end

          private

          attr_reader :profile_read_model
        end
      end
    end
  end
end
