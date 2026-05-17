# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    module Presentation
      class RankingCatalog
        Descriptor = Struct.new(:column, :title_key, :label_key, keyword_init: true)

        RANKINGS = {
          %w[repositories top] => Descriptor.new(
            column: :stargazers_count,
            title_key: 'rankings.title.repositories.top',
            label_key: 'rankings.metric.stars'
          ),
          %w[repositories trending] => Descriptor.new(
            column: :monthly_stars_delta,
            title_key: 'rankings.title.repositories.trending',
            label_key: 'rankings.metric.new_stars'
          ),
          %w[users active] => Descriptor.new(
            column: :public_activity_count,
            title_key: 'rankings.title.users.active',
            label_key: 'rankings.metric.events'
          ),
          %w[users top] => Descriptor.new(
            column: :total_stars,
            title_key: 'rankings.title.users.top',
            label_key: 'rankings.metric.stars'
          ),
          %w[users trending] => Descriptor.new(
            column: :monthly_stars_delta,
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
