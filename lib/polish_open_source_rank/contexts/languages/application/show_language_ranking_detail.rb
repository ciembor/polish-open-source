# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Languages
      module Application
        class ShowLanguageRankingDetail
          def initialize(language_ranking_read_model:)
            @language_ranking_read_model = language_ranking_read_model
          end

          def call(metric:, period_start:, limit: 100)
            language_ranking_read_model.ranked_languages(metric: metric, period_start: period_start, limit: limit)
          end

          private

          attr_reader :language_ranking_read_model
        end
      end
    end
  end
end
