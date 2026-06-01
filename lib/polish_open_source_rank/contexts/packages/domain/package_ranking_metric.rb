# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Domain
        module PackageRankingMetric
          Metric = Data.define(:slug, :key, :ecosystems)

          METRICS = [
            Metric.new(slug: 'top', key: 'downloads_30d', ecosystems: %w[npm crates packagist homebrew]),
            Metric.new(slug: 'downloads', key: 'downloads_total', ecosystems: %w[crates rubygems hex packagist nuget]),
            Metric.new(slug: 'dependents', key: 'dependents_count', ecosystems: %w[rubygems]),
            Metric.new(slug: 'stars', key: 'repository_stars_count', ecosystems: Ecosystem::SUPPORTED),
            Metric.new(slug: 'trending', key: 'repository_stars_delta', ecosystems: Ecosystem::SUPPORTED)
          ].freeze

          module_function

          def all(ecosystem: nil)
            return METRICS unless ecosystem

            METRICS.select { |metric| metric.ecosystems.include?(ecosystem) }
          end

          def keys(ecosystem: nil)
            all(ecosystem: ecosystem).map(&:key)
          end

          def slugs(ecosystem: nil)
            all(ecosystem: ecosystem).map(&:slug)
          end

          def key_for_slug(slug)
            metric = METRICS.find { |candidate| candidate.slug == slug.to_s }
            metric&.key
          end

          def supported_key?(key)
            keys.include?(key.to_s)
          end

          def supported_for_ecosystem?(ecosystem, key)
            keys(ecosystem: ecosystem).include?(key.to_s)
          end

          def slugs_pattern
            slugs.join('|')
          end
        end
      end
    end
  end
end
