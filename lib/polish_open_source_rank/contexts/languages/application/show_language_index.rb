# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Languages
      module Application
        class ShowLanguageIndex
          def initialize(language_ranking_read_model:)
            @language_ranking_read_model = language_ranking_read_model
          end

          def call(period_start:, limit: 10)
            language_ranking_read_model.rankings(period_start: period_start, limit: limit)
          end

          private

          attr_reader :language_ranking_read_model
        end
      end
    end
  end
end
