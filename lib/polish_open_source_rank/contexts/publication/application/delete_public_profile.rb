# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Publication
      module Application
        class DeletePublicProfile
          def initialize(profile_repository:)
            @profile_repository = profile_repository
          end

          def call(platform:, source_id:)
            profile_repository.redact_profile(platform: platform, source_id: source_id)
          end

          private

          attr_reader :profile_repository
        end
      end
    end
  end
end
