# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    module Presentation
      class PublicPageState
        def initialize(view_context)
          @view_context = view_context
        end

        def rankings(scope:, period_slug:, page:)
          {
            user_rankings: page.user_rankings,
            repository_rankings: page.repository_rankings,
            organization_rankings: page.organization_rankings,
            organization_repository_rankings: page.organization_repository_rankings,
            title: translate_rankings_title(scope, period_slug),
            description: translate_rankings_description(scope, period_slug),
            canonical_path: canonical_rankings_path(scope, period_slug)
          }
        end

        def editions(page:, year:)
          {
            years: page.years,
            year: page.year,
            editions: page.editions,
            newer_year: page.newer_year,
            older_year: page.older_year,
            title: year ? t('editions.seo.title_year', year: year) : t('editions.seo.title'),
            description: t('editions.seo.description'),
            canonical_path: year ? view_context.editions_path(year) : view_context.editions_path
          }
        end

        def user_profile(profile:, own_profile:)
          display_name = display_name(profile)
          source_name = call_view(:platform_name, profile.fetch(:platform))

          {
            repositories: profile.fetch(:repositories),
            title: t('users.seo.title', user: display_name, platform: source_name),
            description: t('users.seo.description', user: display_name, platform: source_name),
            canonical_path: call_view(:user_profile_path, profile),
            discord_panel: own_profile ? call_view(:show_discord_panel_for, profile) : nil,
            discord_error: own_profile ? view_context.session.delete(:discord_error) : nil,
            show_profile_badges: own_profile
          }
        end

        def repository_profile(repository:, own_repository:)
          source_name = call_view(:platform_name, repository.fetch(:platform))

          {
            title: t('repositories.seo.title', repository: repository.fetch(:full_name), platform: source_name),
            description: t(
              'repositories.seo.description',
              repository: repository.fetch(:full_name),
              platform: source_name
            ),
            canonical_path: call_view(:repository_profile_path, repository),
            show_repository_badge: own_repository
          }
        end

        def organization_profile(organization:)
          display_name = display_name(organization)
          source_name = call_view(:platform_name, organization.fetch(:platform))

          {
            repositories: organization.fetch(:repositories),
            title: t('organizations.seo.title', organization: display_name, platform: source_name),
            description: t('organizations.seo.description', organization: display_name, platform: source_name),
            canonical_path: call_view(:organization_profile_path, organization)
          }
        end

        def organization_repository_profile(repository:)
          source_name = call_view(:platform_name, repository.fetch(:platform))

          {
            title: t(
              'organization_repositories.seo.title',
              repository: repository.fetch(:full_name),
              platform: source_name
            ),
            description: t(
              'organization_repositories.seo.description',
              repository: repository.fetch(:full_name),
              platform: source_name
            ),
            canonical_path: call_view(:organization_repository_profile_path, repository)
          }
        end

        def ranking_detail(scope:, period_slug:, kind:, metric:, ranking:)
          ranking_name = call_view(:ranking_title, kind, metric)
          scope_name = call_view(:scope_name, scope)
          period_name = seo_period_label(period_slug)

          {
            ranking: ranking,
            title: t('rankings.seo.detail_title', ranking: ranking_name, scope: scope_name, period: period_name),
            description: ranking_detail_description(kind, metric, ranking_name, scope_name, period_name),
            canonical_path: ranking_detail_path(scope, period_slug, kind, metric)
          }
        end

        private

        attr_reader :view_context

        def t(key, values = {})
          call_view(:t, key, values)
        end

        def canonical_rankings_path(scope, period_slug)
          return call_view(:period_base_path, period_slug) if scope.fetch(:slug) == 'poland'

          call_view(:city_path, scope.fetch(:slug), period_slug: period_slug)
        end

        def display_name(resource)
          resource[:name].to_s.empty? ? resource.fetch(:login) : resource[:name]
        end

        def seo_period_label(period_slug)
          return t('rankings.seo.current_period') if period_slug == 'latest'

          call_view(:period_label, Date.parse("#{period_slug}-01").iso8601)
        end

        def translate_rankings_title(scope, period_slug)
          key = period_slug == 'latest' ? 'rankings.seo.title_latest' : 'rankings.seo.title_period'
          t(key, scope: call_view(:scope_name, scope), period: seo_period_label(period_slug))
        end

        def translate_rankings_description(scope, period_slug)
          key = period_slug == 'latest' ? 'rankings.seo.description_latest' : 'rankings.seo.description_period'
          t(key, scope: call_view(:scope_name, scope), period: seo_period_label(period_slug))
        end

        def ranking_detail_description(kind, metric, ranking_name, scope_name, period_name)
          t(
            'rankings.seo.detail_description',
            ranking: ranking_name,
            scope: scope_name,
            metric: call_view(:ranking_metric_label, kind, metric),
            period: period_name
          )
        end

        def ranking_detail_path(scope, period_slug, kind, metric)
          call_view(:ranking_path, kind, metric, period_slug: period_slug, scope_slug: scope.fetch(:slug))
        end

        def call_view(method_name, *, **)
          view_context.send(method_name, *, **)
        end
      end
    end
  end
end
