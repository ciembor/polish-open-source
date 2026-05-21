# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    module Controllers
      module PublicController
        include SitemapSupport

        private

        def render_city(period_slug, slug)
          halt 404 unless Contexts::Ranking::Domain::LocationCatalog.city_slugs.include?(slug)

          render_rankings(period_slug, slug)
        end

        def render_city_ranking_detail(period_slug, slug, kind, metric)
          halt 404 unless Contexts::Ranking::Domain::LocationCatalog.city_slugs.include?(slug)

          render_ranking_detail(period_slug, slug, kind, metric)
        end

        def render_rankings(period_slug, scope)
          @scope = scope_data(scope)
          @period_slug = period_slug
          @period = period_for(period_slug)
          public_html_cache!('rankings', period_slug, scope, @period, public_cache_revision(@period))
          page = show_rankings.call(scope: scope, period_start: @period)
          @user_rankings = page.user_rankings
          @repository_rankings = page.repository_rankings
          @title = "#{scope_name(@scope)} open-source ranking"
          @description = t('rankings.seo.description', scope: scope_name(@scope))
          @canonical_path = if scope == 'poland'
                              period_base_path(period_slug)
                            else
                              city_path(scope,
                                        period_slug: period_slug)
                            end
          erb :rankings
        end

        def render_editions(year = nil)
          page = list_editions.call(year: year)
          halt 404 unless page

          @years = page.years
          @year = page.year
          public_html_cache!('editions', @year || 'index', latest_public_cache_key)
          @editions = page.editions
          @newer_year = page.newer_year
          @older_year = page.older_year
          @title = year ? "#{t('editions.title')} #{year}" : t('editions.title')
          @description = t('editions.seo.description')
          @canonical_path = year ? editions_path(year) : editions_path
          erb :editions
        end

        def render_user_profile(platform, login)
          @period_slug = 'latest'
          @period = latest_period
          @profile = show_user_profile.call(platform: platform, login: login, period_start: @period)
          halt 404 unless @profile
          profile_cache!(@profile)

          @repositories = @profile.fetch(:repositories)
          display_name = @profile[:name].to_s.empty? ? @profile.fetch(:login) : @profile[:name]
          source_name = platform_name(@profile.fetch(:platform))
          @title = "#{display_name} - #{source_name} profile"
          @description = t('users.seo.description', user: display_name, platform: source_name)
          @canonical_path = user_profile_path(@profile)
          @discord_panel = show_discord_panel_for(@profile) if own_profile?(@profile) && @profile[:period_start]
          @show_profile_badges = own_profile?(@profile)
          erb :user_profile
        end

        def render_repository_profile(platform, owner, name)
          @period_slug = 'latest'
          @period = latest_period
          @repository = show_repository_profile.call(platform: platform, owner: owner, name: name,
                                                     period_start: @period)
          halt 404 unless @repository
          repository_profile_cache!(@repository)

          source_name = platform_name(@repository.fetch(:platform))
          @title = "#{@repository.fetch(:full_name)} - #{source_name} project"
          @description = t(
            'repositories.seo.description',
            repository: @repository.fetch(:full_name),
            platform: source_name
          )
          @canonical_path = repository_profile_path(@repository)
          @show_repository_badge = own_repository?(@repository)
          erb :repository_profile
        end

        def render_ranking_detail(period_slug, scope, kind, metric)
          halt 404 unless ranking_metric?(kind, metric)

          @scope = scope_data(scope)
          @period_slug = period_slug
          @period = period_for(period_slug)
          @kind = kind
          @metric = metric
          public_html_cache!('ranking-detail', period_slug, scope, kind, metric, @period,
                             public_cache_revision(@period))
          @ranking = show_ranking_detail.call(scope: scope, kind: kind, metric: metric, period_start: @period)
          @title = "#{scope_name(@scope)} #{ranking_title(kind, metric)}"
          @description = "#{ranking_title(kind, metric)} - #{scope_name(@scope)}."
          @canonical_path = ranking_path(kind, metric, period_slug: period_slug, scope_slug: scope)
          erb :ranking_detail
        end
      end
    end
  end
end
