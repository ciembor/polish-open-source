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
      end
    end
  end
end
