# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    module Controllers
      module PackageRankingController
        private

        def render_package_ranking_detail(period_slug, ecosystem, metric_slug, repository_kind_slug: nil)
          metric = Contexts::Packages::Domain::PackageRankingMetric.key_for_slug(metric_slug)
          repository_kind = repository_kind_for_slug(repository_kind_slug)
          unless Contexts::Packages::Domain::PackageRankingMetric.supported_for_ecosystem?(ecosystem, metric)
            halt_negative_public_404!('package-ranking-unsupported-metric', period_slug, ecosystem, metric_slug)
          end
          @period_slug = period_slug
          @period = period_for(period_slug)
          paginator = ranking_paginator
          cache_package_ranking!(period_slug, ecosystem, metric_slug, repository_kind_slug, paginator.number)
          render_package_ranking_page(period_slug, ecosystem, metric_slug, metric, repository_kind, paginator)
        end

        def render_package_ranking_page(period_slug, ecosystem, metric_slug, metric, repository_kind, paginator)
          pagination = fetch_ranking_page(paginator) do |limit:, offset:|
            packages.show_package_ranking_detail.call(
              ecosystem: ecosystem,
              metric: metric,
              period_start: @period,
              repository_kind: repository_kind,
              limit: limit,
              offset: offset
            )
          end
          halt 404 if repository_kind && pagination.records.empty?

          page = package_ranking_page(period_slug, ecosystem, metric_slug, metric, repository_kind, pagination)
          assign_public_page(public_page_state.package_ranking_detail(page))
          erb :'packages/ranking_detail'
        end

        def cache_package_ranking!(period_slug, ecosystem, metric_slug, repository_kind_slug, page)
          public_html_cache!(
            'package-ranking-detail',
            period_slug,
            ecosystem,
            metric_slug,
            repository_kind_slug,
            page,
            @period,
            public_cache_revision(@period)
          )
        end

        def repository_kind_for_slug(slug)
          Presentation::PublicRepositoryKind.key_for_slug(slug) if slug
        end

        def package_ranking_page(period_slug, ecosystem, metric_slug, metric, repository_kind, pagination)
          {
            period_slug: period_slug,
            period_start: @period,
            ecosystem: ecosystem,
            metric_slug: metric_slug,
            metric: metric,
            repository_kind: repository_kind,
            pagination: pagination
          }
        end
      end
    end
  end
end
