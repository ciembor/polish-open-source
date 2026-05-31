# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Ranking
      module Domain
        class RankingPolicy
          RANKING_LIMIT = 100
          TRENDING_COLUMN = 'monthly_stars_delta'
          Metric = Struct.new(:key, :column, :trending, keyword_init: true) do
            def trending?
              trending
            end
          end

          USER_RANKINGS = {
            top: Metric.new(key: :user_top, column: 'total_stars', trending: false),
            trending: Metric.new(key: :user_trending, column: TRENDING_COLUMN, trending: true),
            active: Metric.new(key: :user_active, column: 'merged_pull_requests_count', trending: false)
          }.freeze
          ORGANIZATION_RANKINGS = {
            top: Metric.new(key: :organization_top, column: 'total_stars', trending: false),
            trending: Metric.new(key: :organization_trending, column: TRENDING_COLUMN, trending: true)
          }.freeze
          REPOSITORY_RANKINGS = {
            top: Metric.new(key: :repository_top, column: 'stargazers_count', trending: false),
            trending: Metric.new(key: :repository_trending, column: TRENDING_COLUMN, trending: true)
          }.freeze
          ORGANIZATION_REPOSITORY_RANKINGS = {
            top: Metric.new(key: :organization_repository_top, column: 'stargazers_count', trending: false),
            trending: Metric.new(key: :organization_repository_trending, column: TRENDING_COLUMN, trending: true)
          }.freeze
          METRICS_BY_KEY = (
            USER_RANKINGS.values +
            ORGANIZATION_RANKINGS.values +
            REPOSITORY_RANKINGS.values +
            ORGANIZATION_REPOSITORY_RANKINGS.values
          ).to_h do |metric|
            [metric.key, metric]
          end.freeze
          USER_TIE_BREAKER = 'login COLLATE NOCASE ASC'
          ORGANIZATION_TIE_BREAKER = 'login COLLATE NOCASE ASC'
          REPOSITORY_TIE_BREAKER = 'owner_login COLLATE NOCASE ASC, repository_github_id ASC'
          ORGANIZATION_REPOSITORY_TIE_BREAKER =
            'organization_login COLLATE NOCASE ASC, repository_github_id ASC'

          def self.column(key)
            metric(key).column
          end

          def self.metric(key)
            METRICS_BY_KEY.fetch(key)
          end

          def self.trending?(column)
            column == TRENDING_COLUMN
          end

          def self.bounded_limit(limit)
            limit.to_i.clamp(1, RANKING_LIMIT)
          end
        end
      end
    end
  end
end
