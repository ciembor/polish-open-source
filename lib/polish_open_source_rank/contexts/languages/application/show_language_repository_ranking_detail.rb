# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Languages
      module Application
        class ShowLanguageRepositoryRankingDetail
          def initialize(language_ranking_read_model:)
            @language_ranking_read_model = language_ranking_read_model
          end

          def call(language:, metric:, repository_kind:, period_start:, limit: 100)
            language_ranking_read_model.ranked_repositories(
              language: language,
              metric: metric,
              period_start: period_start,
              limit: limit,
              repository_kind: repository_kind
            )
          end

          private

          attr_reader :language_ranking_read_model
        end
      end
    end
  end
end
