# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    module Routes
      module LanguageRoutes
        def self.registered(app)
          app.get('/languages') { render_language_index('latest') }
          app.get('/latest/languages/:metric') do
            render_language_ranking_detail('latest', params.fetch('metric'))
          end
          app.get(%r{/(\d{4}-\d{2})/languages}) { |period_slug| render_language_index(period_slug) }
          app.get(period_language_metric_route) do |period_slug, metric|
            render_language_ranking_detail(period_slug, metric)
          end
        end

        class << self
          private

          def period_language_metric_route
            Regexp.new("/(\\d{4}-\\d{2})/languages/(#{language_metric_slugs})")
          end

          def language_metric_slugs
            Contexts::Languages::Domain::LanguageRankingMetric.slugs_pattern
          end
        end
      end
    end
  end
end
