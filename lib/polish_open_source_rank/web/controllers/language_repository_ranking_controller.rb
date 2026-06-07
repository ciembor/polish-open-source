# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    module Controllers
      module LanguageRepositoryRankingController
        private

        def render_language_repository_ranking_detail(period_slug, language, repository_kind_slug, metric_slug,
                                                      page = nil)
          repository_kind = language_repository_kind_for_slug(repository_kind_slug)
          metric = Contexts::Languages::Domain::LanguageRepositoryRankingMetric.key_for_slug(metric_slug)

          @period_slug = period_slug
          @period = period_for(period_slug)
          paginator = ranking_paginator(page)
          cache_language_repository_ranking!(period_slug, language, repository_kind_slug, metric_slug, paginator.number)
          pagination = language_repository_ranking(language, repository_kind, metric, paginator)
          halt 404 if pagination.records.empty?

          render_language_repository_ranking_page(
            period_slug,
            language,
            repository_kind,
            metric_slug,
            metric,
            pagination
          )
        end

        def render_language_repository_ranking_page(period_slug, language, repository_kind, metric_slug, metric,
                                                    pagination)
          page = language_repository_ranking_page(
            period_slug,
            language,
            repository_kind,
            metric_slug,
            metric,
            pagination
          )
          assign_public_page(public_page_state.language_repository_ranking_detail(page))
          erb :'languages/repository_ranking_detail'
        end

        def cache_language_repository_ranking!(period_slug, language, repository_kind_slug, metric_slug, page)
          public_html_cache!(
            'language-repository-ranking-detail',
            period_slug,
            language,
            repository_kind_slug,
            metric_slug,
            page,
            @period,
            public_cache_revision(@period)
          )
        end

        def language_repository_ranking(language, repository_kind, metric, paginator)
          fetch_ranking_page(paginator) do |limit:, offset:|
            languages.show_language_repository_ranking_detail.call(
              language: language,
              metric: metric,
              repository_kind: repository_kind,
              period_start: @period,
              limit: limit,
              offset: offset
            )
          end
        end

        def language_repository_kind_for_slug(slug)
          Presentation::PublicRepositoryKind.key_for_slug(slug)
        end

        def language_repository_ranking_page(period_slug, language, repository_kind, metric_slug, metric, pagination)
          {
            period_slug: period_slug,
            period_start: @period,
            language: language,
            repository_kind: repository_kind,
            metric_slug: metric_slug,
            metric: metric,
            pagination: pagination
          }
        end
      end
    end
  end
end
