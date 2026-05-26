# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    module Controllers
      module LanguageController
        private

        def render_language_index(period_slug)
          @period_slug = period_slug
          @period = period_for(period_slug)
          public_html_cache!('languages', period_slug, @period, public_cache_revision(@period))
          assign_public_page(
            public_page_state.language_index(
              period_slug: period_slug,
              period_start: @period,
              cards: show_language_index.call(period_start: @period)
            )
          )
          erb :'languages/index'
        end

        def render_language_ranking_detail(period_slug, metric_slug)
          metric = Contexts::Languages::Domain::LanguageRankingMetric.key_for_slug(metric_slug)
          halt 404 unless metric

          @period_slug = period_slug
          @period = period_for(period_slug)
          public_html_cache!(
            'language-ranking-detail',
            period_slug,
            metric_slug,
            @period,
            public_cache_revision(@period)
          )
          assign_language_ranking_page(period_slug, metric_slug, metric)
          erb :'languages/ranking_detail'
        end

        def render_language(period_slug, language)
          @period_slug = period_slug
          @period = period_for(period_slug)
          public_html_cache!('language', period_slug, language, @period, public_cache_revision(@period))
          ranking_groups = show_language.call(language: language, period_start: @period, limit: 10)
          halt 404 unless ranking_groups.values.any? { |rankings| rankings.values.any?(&:any?) }

          assign_public_page(
            public_page_state.language(
              period_slug: period_slug,
              period_start: @period,
              language: language,
              ranking_groups: ranking_groups
            )
          )
          erb :'languages/show'
        end

        def assign_language_ranking_page(period_slug, metric_slug, metric)
          ranking = show_language_ranking_detail.call(metric: metric, period_start: @period)
          assign_public_page(
            public_page_state.language_ranking_detail(
              period_slug: period_slug,
              period_start: @period,
              metric_slug: metric_slug,
              metric: metric,
              ranking: ranking
            )
          )
        end
      end
    end
  end
end
