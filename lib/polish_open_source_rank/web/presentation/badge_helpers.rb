# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    module Presentation
      module BadgeHelpers
        def repository_badge_path(repository)
          "#{repository_profile_path(repository).sub('/repositories/', '/badges/repositories/')}.svg"
        end

        def user_badge_path(user)
          "#{user_profile_path(user).sub('/users/', '/badges/users/')}.svg"
        end

        def organization_badge_path(organization)
          "#{organization_profile_path(organization).sub('/organizations/', '/badges/organizations/')}.svg"
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
