# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    module Routes
      module LanguageRoutes
        def self.registered(app)
          app.get('/languages') { render_language_index('latest') }
          app.get(latest_language_repository_metric_route) do |language, repository_kind, metric|
            render_language_repository_ranking_detail('latest', language, repository_kind, metric)
          end
          app.get(latest_language_metric_route) do |metric|
            render_language_ranking_detail('latest', metric)
          end
          app.get(%r{/latest/languages/([^/]+)}) do |language|
            render_language('latest', language)
          end
          app.get(%r{/(\d{4}-\d{2})/languages}) { |period_slug| render_language_index(period_slug) }
          app.get(period_language_repository_metric_route) do |period_slug, language, repository_kind, metric|
            render_language_repository_ranking_detail(period_slug, language, repository_kind, metric)
          end
          app.get(period_language_metric_route) do |period_slug, metric|
            render_language_ranking_detail(period_slug, metric)
          end
          app.get(%r{/(\d{4}-\d{2})/languages/([^/]+)}) do |period_slug, language|
            render_language(period_slug, language)
          end
        end

        class << self
          private

          def latest_language_repository_metric_route
            Regexp.new("/latest/languages/([^/]+)/(#{repository_kind_slugs})/(#{repository_metric_slugs})")
          end

          def period_language_repository_metric_route
            Regexp.new(
              "/(\\d{4}-\\d{2})/languages/([^/]+)/(#{repository_kind_slugs})/(#{repository_metric_slugs})"
            )
          end

          def latest_language_metric_route
            Regexp.new("/latest/languages/(#{language_metric_slugs})")
          end

          def period_language_metric_route
            Regexp.new("/(\\d{4}-\\d{2})/languages/(#{language_metric_slugs})")
          end

          def language_metric_slugs
            Contexts::Languages::Domain::LanguageRankingMetric.slugs_pattern
          end

          def repository_metric_slugs
            Contexts::Languages::Domain::LanguageRepositoryRankingMetric.slugs_pattern
          end

          def repository_kind_slugs
            'repositories|users|organizations'
          end
        end
      end
    end
  end
end
