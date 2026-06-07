# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Publication
      module Application
        class ShowRankingDetail
          def initialize(ranking_read_model:)
            @ranking_read_model = ranking_read_model
          end

          RANKINGS = {
            'users' => [:ranked_user_metric, Contexts::Ranking::Domain::RankingPolicy::USER_RANKINGS],
            'repositories' => [:ranked_repository_metric,
                               Contexts::Ranking::Domain::RankingPolicy::REPOSITORY_RANKINGS],
            'organizations' => [:ranked_organization_metric,
                                Contexts::Ranking::Domain::RankingPolicy::ORGANIZATION_RANKINGS],
            'organization-repositories' => [
              :ranked_organization_repository_metric,
              Contexts::Ranking::Domain::RankingPolicy::ORGANIZATION_REPOSITORY_RANKINGS
            ]
          }.freeze

          def call(scope:, kind:, metric:, period_start:, limit: 100, offset: 0)
            return [] unless period_start

            method_name, metrics = RANKINGS.fetch(kind)
            metric_key = metrics.fetch(metric.to_sym).key
            ranking_read_model.public_send(method_name, scope, period_start, metric_key, limit: limit, offset: offset)
          end

          private

          attr_reader :ranking_read_model
        end
      end
    end
  end
end
