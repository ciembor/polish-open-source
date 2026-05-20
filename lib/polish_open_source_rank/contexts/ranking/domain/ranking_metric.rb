# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Ranking
      module Domain
        class RankingMetric
          DEFINITIONS = {
            user_top: 'total_stars',
            user_trending: 'monthly_stars_delta',
            user_active: 'public_activity_count',
            repository_top: 'stargazers_count',
            repository_trending: 'monthly_stars_delta'
          }.freeze

          def self.column(key)
            DEFINITIONS.fetch(key)
          end

          def self.trending?(column)
            column == 'monthly_stars_delta'
          end
        end
      end
    end
  end
end
