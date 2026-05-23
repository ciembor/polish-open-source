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

            case kind
            when 'users'
              ranking_read_model.user_rankings(scope, period_start: period_start).fetch(metric.to_sym)
            when 'repositories'
              ranking_read_model.repository_rankings(scope, period_start: period_start).fetch(metric.to_sym)
            when 'organizations'
              ranking_read_model.organization_rankings(scope, period_start: period_start).fetch(metric.to_sym)
            else
              ranking_read_model.organization_repository_rankings(
                scope,
                period_start: period_start
              ).fetch(metric.to_sym)
            end
          end

          private

          attr_reader :ranking_read_model
        end
      end
    end
  end
end
