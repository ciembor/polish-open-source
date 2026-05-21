# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    module Routes
      module BadgeRoutes
        def self.registered(app)
          app.get('/badges/users/:platform/:login.svg') do
            render_user_badge(params.fetch('platform'), params.fetch('login'))
          end
          app.get('/badges/repositories/:platform/:owner/:name.svg') do
            render_repository_badge(params.fetch('platform'), params.fetch('owner'), params.fetch('name'))
          end
          app.get('/badges/repositories/:owner/:name.svg') do
            render_repository_badge('github', params.fetch('owner'), params.fetch('name'))
          end
        end
      end
    end
  end
end
