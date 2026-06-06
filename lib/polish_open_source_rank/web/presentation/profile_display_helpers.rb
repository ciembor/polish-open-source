# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    module Presentation
      module ProfileDisplayHelpers
        def repository_display_name(repository)
          name = repository[:name].to_s.strip
          return name unless name.empty?

          repository.fetch(:full_name).to_s.split('/').last
        end

        def owner_display_name(name, login)
          login = login.to_s.strip
          return if login.empty?

          name = name.to_s.strip
          return login if name.empty? || name == login

          "#{name} (#{login})"
        end

        def owner_login_display_name(name, login)
          login = login.to_s.strip
          return if login.empty?

          name = name.to_s.strip
          return login if name.empty? || name == login

          "#{login} (#{name})"
        end
      end
    end
  end
end
