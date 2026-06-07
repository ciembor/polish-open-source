# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    module Controllers
      module RankingDetailController
        private

        def render_ranking_detail(period_slug, scope, kind, metric, page = nil)
          halt_negative_public_404!('ranking-detail', period_slug, scope, kind, metric) unless ranking_metric?(
            kind,
            metric
          )

          assign_ranking_detail_context(period_slug, scope, kind, metric)
          paginator = ranking_paginator(page)
          cache_ranking_detail!(period_slug, scope, kind, metric, paginator.number)
          pagination = general_ranking_page(scope, kind, metric, paginator)
          assign_public_page(ranking_detail_state(kind, metric, pagination))
          erb :'rankings/detail'
        end

        def assign_ranking_detail_context(period_slug, scope, kind, metric)
          @scope = scope_data(scope)
          @period_slug = period_slug
          @period = period_for(period_slug)
          @kind = kind
          @metric = metric
        end

        def cache_ranking_detail!(period_slug, scope, kind, metric, page)
          public_html_cache!(
            'ranking-detail',
            period_slug,
            scope,
            kind,
            metric,
            page,
            @period,
            public_cache_revision(@period)
          )
        end

        def general_ranking_page(scope, kind, metric, paginator)
          fetch_ranking_page(paginator) do |limit:, offset:|
            publication.show_ranking_detail.call(
              scope: scope,
              kind: kind,
              metric: metric,
              period_start: @period,
              limit: limit,
              offset: offset
            )
          end
        end

        def ranking_detail_state(kind, metric, pagination)
          public_page_state.ranking_detail(
            scope: @scope,
            period_slug: @period_slug,
            kind: kind,
            metric: metric,
            pagination: pagination
          )
        end
      end
    end
  end
end
