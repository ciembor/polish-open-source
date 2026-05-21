# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    module Controllers
      module BadgeController
        private

        def render_repository_badge(platform, owner, name)
          badge = render_badge.repository(platform: platform, owner: owner, name: name, period_start: latest_period)
          halt 404 unless badge

          content_type 'image/svg+xml'
          public_badge_cache!('repository-badge', platform, owner, name, latest_period)
          settings.badge_renderer.svg(badge, home_url: app_home_url)
        end

        def render_user_badge(platform, login)
          badge = render_badge.user(platform: platform, login: login, period_start: latest_period)
          halt 404 unless badge

          content_type 'image/svg+xml'
          public_badge_cache!('user-badge', platform, login, latest_period)
          settings.badge_renderer.svg(badge, home_url: app_home_url)
        end
      end
    end
  end
end
