# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Publication
      module Application
        # Validates repository profile identity before owner/name are joined into a persisted full name.
        class RepositoryProfileRequest
          def initialize(platform:, owner:, name:, period_start:)
            @platform = Shared::Domain::Platform.coerce(platform)
            @full_name = Shared::Domain::RepositoryFullName.build(owner: owner, name: name)
            @period_start = Shared::Domain::PeriodStart.new(period_start)
          end

          def platform_key
            platform.to_s
          end

          def full_name_key
            full_name.to_s
          end

          def period_start_key
            period_start.to_s
          end

          private

          attr_reader :platform, :full_name, :period_start
        end
      end
    end
  end
end
