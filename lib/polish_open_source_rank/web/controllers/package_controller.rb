# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    module Controllers
      module PackageController
        PACKAGE_RANKING_METRICS = {
          'top' => 'downloads_30d',
          'downloads' => 'downloads_total',
          'dependents' => 'dependents_count'
        }.freeze

        private

        def render_package_index(period_slug)
          @period_slug = period_slug
          @period = period_for(period_slug)
          public_html_cache!('packages', period_slug, @period, public_cache_revision(@period))
          assign_public_page(
            public_page_state.package_index(
              period_slug: period_slug,
              period_start: @period,
              ecosystems: show_package_index.call(period_start: @period)
            )
          )
          erb :packages
        end

        def render_package_ecosystem(period_slug, ecosystem)
          @period_slug = period_slug
          @period = period_for(period_slug)
          public_html_cache!('package-ecosystem', period_slug, ecosystem, @period, public_cache_revision(@period))
          rankings = show_package_ecosystem_rankings.call(ecosystem: ecosystem, period_start: @period, limit: 10)
          halt 404 if rankings.empty?
          assign_public_page(
            public_page_state.package_ecosystem(
              period_slug: period_slug,
              period_start: @period,
              ecosystem: ecosystem,
              rankings: rankings
            )
          )
          erb :package_ecosystem
        end

        def render_package_ranking_detail(period_slug, ecosystem, metric_slug)
          metric = PACKAGE_RANKING_METRICS[metric_slug]
          halt 404 unless metric
          @period_slug = period_slug
          @period = period_for(period_slug)
          public_html_cache!(
            'package-ranking-detail',
            period_slug,
            ecosystem,
            metric_slug,
            @period,
            public_cache_revision(@period)
          )
          render_package_ranking_page(period_slug, ecosystem, metric_slug, metric)
        end

        def render_package_profile(ecosystem, encoded_name)
          @period_slug = 'latest'
          @period = latest_period
          package_name = decode_package_name_slug(encoded_name)
          halt 404 unless package_name
          @package_profile = show_package_profile.call(
            ecosystem: ecosystem,
            package_name: package_name,
            period_start: @period
          )
          halt 404 unless @package_profile
          public_html_cache!('package-profile', ecosystem, encoded_name, @period, public_cache_revision(@period))
          assign_public_page(public_page_state.package_profile(profile: @package_profile))
          erb :package_profile
        end

        def render_package_ranking_page(period_slug, ecosystem, metric_slug, metric)
          ranking = show_package_ranking_detail.call(ecosystem: ecosystem, metric: metric, period_start: @period)
          assign_public_page(
            public_page_state.package_ranking_detail(
              period_slug: period_slug,
              period_start: @period,
              ecosystem: ecosystem,
              metric_slug: metric_slug,
              metric: metric,
              ranking: ranking
            )
          )
          erb :package_ranking_detail
        end
      end
    end
  end
end
