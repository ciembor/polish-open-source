# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Languages
      module Domain
        module LanguageRepositoryRankingMetric
          Metric = Struct.new(:slug, :key, keyword_init: true)

          METRICS = [
            Metric.new(slug: 'top', key: 'repository_stars_count'),
            Metric.new(slug: 'trending', key: 'repository_stars_delta')
          ].freeze

          module_function

          def all
            METRICS
          end

          def keys
            all.map(&:key)
          end

          def slugs
            all.map(&:slug)
          end

          def key_for_slug(slug)
            all.find { |metric| metric.slug == slug.to_s }&.key
          end

          def supported_key?(key)
            keys.include?(key.to_s)
          end

          def slugs_pattern
            slugs.join('|')
          end
        end
      end
    end
  end
end
