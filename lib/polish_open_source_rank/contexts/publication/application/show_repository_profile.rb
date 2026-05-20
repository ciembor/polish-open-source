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
            profile_read_model.repository_profile(platform, owner, name, period_start: period_start)
          end

          private

          attr_reader :profile_read_model
        end
      end
    end
  end
end
