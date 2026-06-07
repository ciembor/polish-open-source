# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    module Presentation
      module PackageOwnerHelpers
        def package_owner_login(row)
          row[:repository_owner_login].to_s.strip.then { |login| login unless login.empty? }
        end

        def package_owner_profile_link(row)
          login = row[:repository_owner_login].to_s.strip
          return if login.empty?

          resource = {
            platform: row.fetch(:repository_platform),
            login: login,
            name: row[:repository_owner_name]
          }
          path = if row[:repository_kind] == 'organization'
                   organization_profile_path(resource)
                 else
                   user_profile_path(resource)
                 end
          app_path(path)
        end
      end
    end
  end
end
