# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    module Controllers
      module LanguageRepositoryRankingController
        private

        def render_language_repository_ranking_detail(period_slug, language, repository_kind_slug, metric_slug)
          repository_kind = language_repository_kind_for_slug(repository_kind_slug)
          metric = Contexts::Languages::Domain::LanguageRepositoryRankingMetric.key_for_slug(metric_slug)

          @period_slug = period_slug
          @period = period_for(period_slug)
          cache_language_repository_ranking!(period_slug, language, repository_kind_slug, metric_slug)
          ranking = language_repository_ranking(language, repository_kind, metric)
          halt 404 if ranking.empty?

          assign_language_repository_ranking_page(period_slug, language, repository_kind, metric_slug, metric, ranking)
          erb :'languages/repository_ranking_detail'
        end

        def cache_language_repository_ranking!(period_slug, language, repository_kind_slug, metric_slug)
          public_html_cache!(
            'language-repository-ranking-detail',
            period_slug,
            language,
            repository_kind_slug,
            metric_slug,
            @period,
            public_cache_revision(@period)
          )
        end

        def language_repository_ranking(language, repository_kind, metric)
          languages.show_language_repository_ranking_detail.call(
            language: language,
            metric: metric,
            repository_kind: repository_kind,
            period_start: @period
          )
        end

        def assign_language_repository_ranking_page(
          period_slug, language, repository_kind, metric_slug, metric, ranking
        )
          assign_public_page(
            public_page_state.language_repository_ranking_detail(
              {
                period_slug: period_slug,
                period_start: @period,
                language: language,
                repository_kind: repository_kind,
                metric_slug: metric_slug,
                metric: metric,
                ranking: ranking
              }
            )
          )
        end

        def language_repository_kind_for_slug(slug)
          { 'users' => 'user', 'organizations' => 'organization' }[slug]
        end
      end
    end
  end
end
