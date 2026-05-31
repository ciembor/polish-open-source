# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    module Presentation
      class RankingCatalog
        Descriptor = Struct.new(:column, :title_key, :label_key, keyword_init: true)
        RankingPolicy = Contexts::Ranking::Domain::RankingPolicy

        RANKINGS = {
          %w[repositories top] => Descriptor.new(
            column: RankingPolicy.column(:repository_top).to_sym,
            title_key: 'rankings.title.repositories.top',
            label_key: 'rankings.metric.stars'
          ),
          %w[repositories trending] => Descriptor.new(
            column: RankingPolicy.column(:repository_trending).to_sym,
            title_key: 'rankings.title.repositories.trending',
            label_key: 'rankings.metric.new_stars'
          ),
          %w[organizations top] => Descriptor.new(
            column: RankingPolicy.column(:organization_top).to_sym,
            title_key: 'rankings.title.organizations.top',
            label_key: 'rankings.metric.stars'
          ),
          %w[organizations trending] => Descriptor.new(
            column: RankingPolicy.column(:organization_trending).to_sym,
            title_key: 'rankings.title.organizations.trending',
            label_key: 'rankings.metric.new_stars'
          ),
          %w[organization-repositories top] => Descriptor.new(
            column: RankingPolicy.column(:organization_repository_top).to_sym,
            title_key: 'rankings.title.organization_repositories.top',
            label_key: 'rankings.metric.stars'
          ),
          %w[organization-repositories trending] => Descriptor.new(
            column: RankingPolicy.column(:organization_repository_trending).to_sym,
            title_key: 'rankings.title.organization_repositories.trending',
            label_key: 'rankings.metric.new_stars'
          ),
          %w[users active] => Descriptor.new(
            column: RankingPolicy.column(:user_active).to_sym,
            title_key: 'rankings.title.users.active',
            label_key: 'rankings.metric.merged_pull_requests'
          ),
          %w[users top] => Descriptor.new(
            column: RankingPolicy.column(:user_top).to_sym,
            title_key: 'rankings.title.users.top',
            label_key: 'rankings.metric.stars'
          ),
          %w[users trending] => Descriptor.new(
            column: RankingPolicy.column(:user_trending).to_sym,
            title_key: 'rankings.title.users.trending',
            label_key: 'rankings.metric.new_stars'
          )
        }.freeze

        def descriptor(kind, metric)
          RANKINGS.fetch([kind, metric])
        end

        def include?(kind, metric)
          RANKINGS.key?([kind, metric])
        end
      end
    end
  end
end
