# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    module Presentation
      module NavigationHelpers
        def active_nav_link_class(section)
          'is-active' if nav_link_active?(section)
        end

        def nav_link_active?(section)
          active_section?(section.to_sym)
        end

        private

        def active_section?(section)
          {
            people: method(:people_nav_active?),
            organizations: method(:organizations_nav_active?),
            languages: method(:languages_nav_active?),
            packages: method(:packages_nav_active?),
            editions: method(:editions_nav_active?),
            about: method(:about_nav_active?),
            profile: method(:profile_nav_active?)
          }.fetch(section, -> { false }).call
        end

        def people_nav_active?
          return false if profile_nav_active?
          return true if @ranking_section == 'people'
          return true if %w[users repositories].include?(@kind)
          return true if @profile || @repository

          people_section_path?(unlocalized_request_path)
        end

        def organizations_nav_active?
          return true if @ranking_section == 'organizations'
          return true if %w[organizations organization-repositories].include?(@kind)
          return true if @organization || @organization_repository

          organizations_section_path?(unlocalized_request_path)
        end

        def languages_nav_active?
          unlocalized_request_path.match?(%r{\A(?:/(?:latest|\d{4}-\d{2}))?/languages(?:/|$)})
        end

        def packages_nav_active?
          unlocalized_request_path.match?(%r{\A(?:/(?:latest|\d{4}-\d{2}))?/packages(?:/|$)})
        end

        def editions_nav_active?
          @editions || unlocalized_request_path.match?(%r{\A/editions(?:/|$)})
        end

        def about_nav_active?
          about_page? || unlocalized_request_path == '/about'
        end

        def profile_nav_active?
          return false unless current_user

          unlocalized_request_path == current_user_profile_request_path
        end

        def current_user_profile_request_path
          platform = Rack::Utils.escape_path(current_user.fetch(:platform, 'github'))
          login = Rack::Utils.escape_path(current_user.fetch(:login))

          "/users/#{platform}/#{login}"
        end

        def people_section_path?(path)
          return true if path.start_with?('/users/', '/repositories/')

          path.match?(%r{\A/(?:|latest(?:/locations/[^/]+)?|\d{4}-\d{2}(?:/locations/[^/]+)?)
                         (?:/(?:users|repositories)/(?:top|trending|active))?\z}x)
        end

        def organizations_section_path?(path)
          return true if path == '/organizations'
          return true if path.start_with?('/organizations/', '/organization-repositories/')
          return true if latest_or_period_organization_path?(path)
          return true if latest_or_period_organization_repository_path?(path)

          city_organization_detail_path?(path)
        end

        def latest_or_period_organization_path?(path)
          path.match?(
            %r{\A/(?:latest|\d{4}-\d{2})/organizations(?:/locations/[^/]+)?(?:/(?:top|trending|members))?\z}
          )
        end

        def latest_or_period_organization_repository_path?(path)
          path.match?(%r{\A/(?:latest|\d{4}-\d{2})/organization-repositories/(?:top|trending)\z})
        end

        def city_organization_detail_path?(path)
          path.match?(%r{\A/(?:latest|\d{4}-\d{2})/locations/[^/]+/
                         (?:organizations/(?:top|trending|members)|organization-repositories/(?:top|trending))\z}x)
        end
      end
    end
  end
end
