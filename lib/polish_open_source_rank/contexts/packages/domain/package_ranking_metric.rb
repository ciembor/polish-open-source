# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Domain
        module PackageRankingMetric
          Metric = Struct.new(:slug, :key, keyword_init: true)

          METRICS = [
            Metric.new(slug: 'top', key: 'downloads_30d'),
            Metric.new(slug: 'downloads', key: 'downloads_total'),
            Metric.new(slug: 'dependents', key: 'dependents_count')
          ].freeze

          module_function

          def all
            METRICS
          end

          def keys
            METRICS.map(&:key)
          end

          def slugs
            METRICS.map(&:slug)
          end

          def key_for_slug(slug)
            metric = METRICS.find { |candidate| candidate.slug == slug.to_s }
            metric&.key
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
