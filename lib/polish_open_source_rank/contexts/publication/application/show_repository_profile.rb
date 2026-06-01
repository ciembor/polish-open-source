# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Publication
      module Application
        class ShowRepositoryProfile
          def initialize(profile_read_model:)
            @profile_read_model = profile_read_model
          end

          def call(platform:, owner:, name:, period_start:)
            request = RepositoryProfileRequest.new(platform: platform, owner: owner, name: name,
                                                   period_start: period_start)
            profile = profile_read_model.repository_profile(
              request.platform_key,
              request.full_name_key,
              period_start: request.period_start_key
            )
            profile && RepositoryPage.new(profile)
          end

          private

          attr_reader :profile_read_model
        end
      end
    end
  end
end
