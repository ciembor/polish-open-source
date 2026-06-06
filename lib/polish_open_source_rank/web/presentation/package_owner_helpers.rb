# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    module Presentation
      module PackageOwnerHelpers
        def package_owner_display_name(row)
          login = row[:repository_owner_login].to_s
          return if login.empty?

          name = row[:repository_owner_name].to_s
          return login if name.empty? || name.casecmp?(login)

          "#{name} (#{login})"
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
