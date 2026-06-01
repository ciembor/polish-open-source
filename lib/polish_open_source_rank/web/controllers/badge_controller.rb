# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    module Controllers
      module BadgeController
        private

        def render_repository_badge(platform, owner, name)
          render_cached_badge('repository-badge', platform, owner, name) do |period|
            publication.render_badge.repository(platform: platform, owner: owner, name: name, period_start: period)
          end
        end

        def render_user_badge(platform, login)
          render_cached_badge('user-badge', platform, login) do |period|
            publication.render_badge.user(platform: platform, login: login, period_start: period)
          end
        end

        def render_organization_badge(platform, login)
          render_cached_badge('organization-badge', platform, login) do |period|
            publication.render_badge.organization(platform: platform, login: login, period_start: period)
          end
        end

        def render_cached_badge(*cache_parts)
          period = latest_period

          content_type 'image/svg+xml'
          public_badge_cache!(*cache_parts, period) if conditional_cache_request?
          badge = yield period
          halt 404 unless badge

          public_badge_cache!(*cache_parts, period) unless response.headers['ETag']
          settings.badge_renderer.svg(badge, home_url: app_home_url)
        end

        def conditional_cache_request?
          !request.get_header('HTTP_IF_NONE_MATCH').to_s.empty?
        end
      end
    end
  end
end
