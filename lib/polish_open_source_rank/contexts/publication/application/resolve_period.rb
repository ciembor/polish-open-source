# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Publication
      module Application
        class ResolvePeriod
          PERIOD_SLUG = /\A\d{4}-\d{2}\z/

          def initialize(period_read_model:)
            @period_read_model = period_read_model
          end

          def call(period_slug:)
            return period_read_model.latest_period if period_slug == 'latest'
            return unless period_slug.match?(PERIOD_SLUG)

            period_start = Shared::Domain::Period.parse(period_slug).start_date.to_s
            period_start if period_read_model.recorded_period?(period_start)
          rescue Date::Error
            nil
          end

          private

          attr_reader :period_read_model
        end
      end
    end
  end
end
