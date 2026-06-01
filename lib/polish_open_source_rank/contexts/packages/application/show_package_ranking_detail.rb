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

          def call(ecosystem:, metric:, period_start:, limit: DEFAULT_LIMIT, repository_kind: nil)
            return [] unless period_start

            ecosystem = Domain::Ecosystem.require_supported!(ecosystem)
            arguments = {
              ecosystem: ecosystem,
              period_start: period_start,
              metric: metric,
              limit: limit
            }
            arguments[:repository_kind] = repository_kind if repository_kind
            package_ranking_read_model.ranked_packages(**arguments)
          end

          private

          attr_reader :package_ranking_read_model
        end
      end
    end
  end
end
