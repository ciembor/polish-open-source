# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    module Presentation
      module ProfilePathHelpers
        def user_profile_path(user)
          platform = Rack::Utils.escape_path(user.fetch(:platform, 'github'))
          login = Rack::Utils.escape_path(user.fetch(:login))
          localized_public_path("/users/#{platform}/#{login}", locale: current_locale)
        end

        def organization_profile_path(organization)
          platform = Rack::Utils.escape_path(organization.fetch(:platform, 'github'))
          login = Rack::Utils.escape_path(organization.fetch(:login))
          localized_public_path("/organizations/#{platform}/#{login}", locale: current_locale)
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
      end
    end
  end
end
