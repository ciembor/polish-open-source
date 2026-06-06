# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    module Presentation
      module ProfilePathHelpers
        def user_profile_path(user)
          platform = Rack::Utils.escape_path(user.fetch(:platform, 'github'))
          login = Rack::Utils.escape_path(user.fetch(:login))
          path = "/users/#{platform}/#{login}"
          slug = resource_name_slug(user)
          path = "#{path}/#{Rack::Utils.escape_path(slug)}" if slug
          localized_public_path(path, locale: current_locale)
        end

        def organization_profile_path(organization)
          platform = Rack::Utils.escape_path(organization.fetch(:platform, 'github'))
          login = Rack::Utils.escape_path(organization.fetch(:login))
          path = "/organizations/#{platform}/#{login}"
          slug = resource_name_slug(organization)
          path = "#{path}/#{Rack::Utils.escape_path(slug)}" if slug
          localized_public_path(path, locale: current_locale)
        end

        def repository_profile_path(repository)
          platform = Rack::Utils.escape_path(repository.fetch(:platform, 'github'))
          owner, name = repository.fetch(:full_name).split('/', 2)
          localized_public_path(
            "/repositories/#{platform}/#{Rack::Utils.escape_path(owner)}/#{Rack::Utils.escape_path(name)}",
            locale: current_locale
          )
        end

        def organization_repository_profile_path(repository)
          platform = Rack::Utils.escape_path(repository.fetch(:platform, 'github'))
          owner, name = repository.fetch(:full_name).split('/', 2)
          localized_public_path(
            "/organization-repositories/#{platform}/#{Rack::Utils.escape_path(owner)}/#{Rack::Utils.escape_path(name)}",
            locale: current_locale
          )
        end

        private

        def resource_name_slug(resource)
          name = resource.fetch(:name, '').to_s.strip
          return nil if name.empty?

          slug = seo_slug(name)
          return nil if slug.empty?

          login_slug = seo_slug(resource.fetch(:login))
          return nil if slug.casecmp?(login_slug)

          slug
        end

        def seo_slug(text)
          text.to_s
              .unicode_normalize(:nfkd)
              .gsub(/\p{Mn}/, '')
              .downcase
              .gsub(/[^a-z0-9]+/, '-')
              .gsub(/\A-+|-+\z/, '')
        end
      end
    end
  end
end
