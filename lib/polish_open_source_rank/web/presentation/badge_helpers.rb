# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    module Presentation
      module BadgeHelpers
        def repository_badge_path(repository)
          platform = Rack::Utils.escape_path(repository.fetch(:platform, 'github'))
          owner, name = repository.fetch(:full_name).split('/', 2)
          "/badges/repositories/#{platform}/#{Rack::Utils.escape_path(owner)}/#{Rack::Utils.escape_path(name)}.svg"
        end

        def user_badge_path(user)
          platform = Rack::Utils.escape_path(user.fetch(:platform, 'github'))
          login = Rack::Utils.escape_path(user.fetch(:login))
          "/badges/users/#{platform}/#{login}.svg"
        end

        def organization_badge_path(organization)
          platform = Rack::Utils.escape_path(organization.fetch(:platform, 'github'))
          login = Rack::Utils.escape_path(organization.fetch(:login))
          "/badges/organizations/#{platform}/#{login}.svg"
        end

        def linked_badge_markdown(alt, badge_path)
          "[![#{alt}](#{configuration.public_base_url.delete_suffix('/')}#{badge_path})](#{app_home_url})"
        end

        def app_home_url
          "#{configuration.public_base_url.delete_suffix('/')}#{period_base_path('latest')}"
        end
      end
    end
  end
end
