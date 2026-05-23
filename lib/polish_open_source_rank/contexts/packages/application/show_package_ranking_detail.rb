# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Application
        class ShowPackageRankingDetail
          DEFAULT_LIMIT = 100

          def initialize(package_ranking_read_model:)
            @package_ranking_read_model = package_ranking_read_model
          end

          def call(ecosystem:, metric:, period_start:, limit: DEFAULT_LIMIT)
            return [] unless period_start

            package_ranking_read_model.ranked_packages(
              ecosystem: ecosystem,
              period_start: period_start,
              metric: metric,
              limit: limit
            )
          end

          private

          attr_reader :package_ranking_read_model
        end
      end
    end
  end
end
