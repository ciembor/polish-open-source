# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Publication
      module Application
        class ShowOrganizationRepositoryProfile
          def initialize(profile_read_model:)
            @profile_read_model = profile_read_model
          end

          def call(platform:, owner:, name:, period_start:)
            profile = profile_read_model.organization_repository_profile(
              platform, owner, name, period_start: period_start
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
