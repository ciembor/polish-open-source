# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Publication
      module Application
        class ShowRankingDetail
          def initialize(ranking_read_model:)
            @ranking_read_model = ranking_read_model
          end

          def call(scope:, kind:, metric:, period_start:)
            return [] unless period_start

            if kind == 'users'
              ranking_read_model.user_rankings(scope, period_start: period_start)
            else
              ranking_read_model.repository_rankings(scope, period_start: period_start)
            end.fetch(metric.to_sym)
          end

          private

          attr_reader :ranking_read_model
        end
      end
    end
  end
end
