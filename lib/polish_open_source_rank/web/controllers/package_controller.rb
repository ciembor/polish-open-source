# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    module Controllers
      module PackageController
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
          erb :'packages/index'
        end

        def render_package_ecosystem(period_slug, ecosystem)
          @period_slug = period_slug
          @period = period_for(period_slug)
          public_html_cache!('package-ecosystem', period_slug, ecosystem, @period, public_cache_revision(@period))
          rankings = show_package_ecosystem_rankings.call(ecosystem: ecosystem, period_start: @period, limit: 10)
          ranking_groups = package_ranking_groups(ecosystem, @period, 10)
          halt 404 if rankings.empty?
          assign_public_page(
            public_page_state.package_ecosystem(
              period_slug: period_slug,
              period_start: @period,
              ecosystem: ecosystem,
              rankings: rankings,
              ranking_groups: ranking_groups
            )
          )
          erb :'packages/ecosystem'
        end

        def package_ranking_groups(ecosystem, period, limit)
          %w[user organization].to_h do |repository_kind|
            [repository_kind.to_sym, show_package_ecosystem_rankings.call(
              ecosystem: ecosystem,
              period_start: period,
              limit: limit,
              repository_kind: repository_kind
            )]
          end
        end
      end
    end
  end
end
