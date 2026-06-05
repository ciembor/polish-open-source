# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    module Routes
      module AuthRoutes
        def self.registered(app)
          register_github_routes(app)
          register_discord_routes(app)
          register_session_routes(app)
          app.register Routes::DevAuthRoutes
        end

        class << self
          private

          def register_github_routes(app)
            app.get '/auth/github' do
              Routes::AuthFlow.new(self).start_github_oauth
            end

            app.get '/auth/github/callback' do
              Routes::AuthFlow.new(self).finish_github_oauth
            end
          end

          def register_discord_routes(app)
            app.get '/auth/discord' do
              Routes::AuthFlow.new(self).start_discord_oauth
            end

            app.get '/auth/discord/callback' do
              Routes::AuthFlow.new(self).finish_discord_oauth
            end
          end

          def register_session_routes(app)
            app.post '/logout' do
              no_store!
              halt 403 unless valid_csrf_token?

              session.clear
              redirect app_path(period_base_path('latest'))
            end
          end
        end
      end
    end
  end
end
