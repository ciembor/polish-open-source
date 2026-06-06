# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    module Routes
      module ProfileRoutes
        def self.register(app)
          register_user_routes(app)
          register_organization_routes(app)
          register_repository_routes(app)
        end

        def self.register_user_routes(app)
          app.get('/users/:platform/:login/:name_slug') do
            render_user_profile(params.fetch('platform'), params.fetch('login'))
          end
          app.get('/users/:platform/:login') { render_user_profile(params.fetch('platform'), params.fetch('login')) }
        end

        def self.register_organization_routes(app)
          app.get('/organizations/:platform/:login/:name_slug') do
            render_organization_profile(params.fetch('platform'), params.fetch('login'))
          end
          app.get('/organizations/:platform/:login') do
            render_organization_profile(params.fetch('platform'), params.fetch('login'))
          end
        end

        def self.register_repository_routes(app)
          app.get('/repositories/:platform/:owner/:name') do
            render_repository_profile(params.fetch('platform'), params.fetch('owner'), params.fetch('name'))
          end
          app.get('/organization-repositories/:platform/:owner/:name') do
            render_organization_repository_profile(
              params.fetch('platform'),
              params.fetch('owner'),
              params.fetch('name')
            )
          end
        end
      end
    end
  end
end
