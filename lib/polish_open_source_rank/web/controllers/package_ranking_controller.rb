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
          cache_package_ranking!(period_slug, ecosystem, metric_slug, repository_kind_slug)
          render_package_ranking_page(period_slug, ecosystem, metric_slug, metric, repository_kind)
        end

        def render_package_ranking_page(period_slug, ecosystem, metric_slug, metric, repository_kind)
          ranking = packages.show_package_ranking_detail.call(
            ecosystem: ecosystem,
            metric: metric,
            period_start: @period,
            repository_kind: repository_kind
          )
          halt 404 if repository_kind && ranking.empty?

          assign_package_ranking_page(period_slug, ecosystem, metric_slug, metric, repository_kind, ranking)
          erb :'packages/ranking_detail'
        end

        def cache_package_ranking!(period_slug, ecosystem, metric_slug, repository_kind_slug)
          public_html_cache!(
            'package-ranking-detail',
            period_slug,
            ecosystem,
            metric_slug,
            repository_kind_slug,
            @period,
            public_cache_revision(@period)
          )
        end

        def assign_package_ranking_page(period_slug, ecosystem, metric_slug, metric, repository_kind, ranking)
          assign_public_page(
            public_page_state.package_ranking_detail(
              {
                period_slug: period_slug,
                period_start: @period,
                ecosystem: ecosystem,
                metric_slug: metric_slug,
                metric: metric,
                repository_kind: repository_kind,
                ranking: ranking
              }
            )
          )
        end

        def repository_kind_for_slug(slug)
          return unless slug

          { 'users' => 'user', 'organizations' => 'organization' }[slug]
        end
      end
    end
  end
end
