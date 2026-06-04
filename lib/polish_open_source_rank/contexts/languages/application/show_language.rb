# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Languages
      module Application
        class ShowLanguage
          REPOSITORY_KINDS = [nil, 'user', 'organization'].freeze

          def initialize(language_ranking_read_model:)
            @language_ranking_read_model = language_ranking_read_model
          end

          def call(language:, period_start:, limit: 10)
            REPOSITORY_KINDS.to_h do |repository_kind|
              [repository_kind_key(repository_kind), language_ranking_read_model.repository_rankings(
                language: language,
                period_start: period_start,
                limit: limit,
                repository_kind: repository_kind
              )]
            end
          end

          private

          attr_reader :language_ranking_read_model

          def repository_kind_key(repository_kind)
            repository_kind ? repository_kind.to_sym : :all
          end
        end
      end
    end
  end
end
