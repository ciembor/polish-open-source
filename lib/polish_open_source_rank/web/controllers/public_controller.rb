# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    module Controllers
      module PublicController
        include SitemapSupport

        CITY_SLUGS = Contexts::Ranking::Domain::LocationCatalog.city_slugs

        private

        def render_city(period_slug, slug, section: 'people')
          halt_negative_public_404!('city', period_slug, slug, section) unless CITY_SLUGS.include?(slug)

          render_rankings(period_slug, slug, section: section)
        end

        def render_city_ranking_detail(period_slug, slug, kind, metric)
          unless CITY_SLUGS.include?(slug)
            halt_negative_public_404!('city-ranking-detail', period_slug, slug, kind, metric)
          end

          render_ranking_detail(period_slug, slug, kind, metric)
        end

        def render_rankings(period_slug, scope, section: 'people')
          @scope = scope_data(scope)
          @period_slug = period_slug
          @ranking_section = section
          @period = period_for(period_slug)
          public_html_cache!('rankings', section, period_slug, scope, @period, public_cache_revision(@period))
          page = publication.show_rankings.call(scope: scope, period_start: @period)
          assign_public_page(
            public_page_state.rankings(scope: @scope, period_slug: @period_slug, section: @ranking_section, page: page)
          )
          erb :'pages/rankings'
        end

        def render_editions(year = nil)
          page = publication.list_editions.call(year: year)
          halt 404 unless page
          public_html_cache!('editions', @year || 'index', latest_public_cache_key)
          assign_public_page(public_page_state.editions(page: page, year: year))
          erb :'pages/editions'
        end

        def render_user_profile(platform, login)
          @period_slug = 'latest'
          @period = latest_period
          @profile = publication.show_user_profile.call(platform: platform, login: login, period_start: @period)
          halt 404 unless @profile
          profile_cache!(@profile)
          assign_public_page(public_page_state.user_profile(profile: @profile, own_profile: own_profile?(@profile)))
          erb :'profiles/user'
        end

        def render_repository_profile(platform, owner, name)
          @period_slug = 'latest'
          @period = latest_period
          @repository = publication.show_repository_profile.call(platform: platform, owner: owner, name: name,
                                                                 period_start: @period)
          halt 404 unless @repository
          repository_profile_cache!(@repository)
          assign_public_page(
            public_page_state.repository_profile(repository: @repository, own_repository: own_repository?(@repository))
          )
          erb :'profiles/repository'
        end

        def render_organization_profile(platform, login)
          @period_slug = 'latest'
          @period = latest_period
          @organization = publication.show_organization_profile.call(platform: platform, login: login,
                                                                     period_start: @period)
          halt 404 unless @organization
          profile_cache!(@organization)
          assign_public_page(public_page_state.organization_profile(organization: @organization))
          erb :'profiles/organization'
        end

        def render_organization_repository_profile(platform, owner, name)
          @period_slug = 'latest'
          @period = latest_period
          @organization_repository = publication.show_organization_repository_profile.call(
            platform: platform,
            owner: owner,
            name: name,
            period_start: @period
          )
          halt 404 unless @organization_repository
          repository_profile_cache!(@organization_repository)
          assign_public_page(public_page_state.organization_repository_profile(repository: @organization_repository))
          erb :'profiles/organization_repository'
        end

        def render_ranking_detail(period_slug, scope, kind, metric)
          unless ranking_metric?(kind, metric)
            halt_negative_public_404!('ranking-detail', period_slug, scope, kind, metric)
          end

          @scope = scope_data(scope)
          @period_slug = period_slug
          @period = period_for(period_slug)
          @kind = kind
          @metric = metric
          public_html_cache!('ranking-detail', period_slug, scope, kind, metric, @period,
                             public_cache_revision(@period))
          assign_public_page public_page_state.ranking_detail(
            scope: @scope,
            period_slug: @period_slug,
            kind: kind,
            metric: metric,
            ranking: publication.show_ranking_detail.call(scope: scope, kind: kind, metric: metric,
                                                          period_start: @period)
          )
          erb :'rankings/detail'
        end

        def assign_public_page(attributes) = attributes.each { |name, value| instance_variable_set("@#{name}", value) }

        def public_page_state = (@public_page_state ||= Presentation::PublicPageState.new(self))
      end
    end
  end
end
