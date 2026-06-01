# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Publication
      module Application
        # Validates platform/login profile lookups before they reach public read models.
        class ProfileRequest
          def initialize(platform:, login:, period_start:)
            @platform = Shared::Domain::Platform.coerce(platform)
            @login = Shared::Domain::Login.new(login)
            @period_start = Shared::Domain::PeriodStart.new(period_start)
          end

          def platform_key
            platform.to_s
          end

          def login_key
            login.to_s
          end

          def period_start_key
            period_start.to_s
          end

          private

          attr_reader :platform, :login, :period_start
        end
      end
    end
  end
end
