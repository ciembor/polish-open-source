# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Ranking
      module Domain
        class RankingMetric
          def self.column(key)
            RankingPolicy.column(key)
          end

          def self.trending?(column)
            RankingPolicy.trending?(column)
          end
        end
      end
    end
  end
end
