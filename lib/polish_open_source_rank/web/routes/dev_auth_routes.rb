# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    module Routes
      module DevAuthRoutes
        def self.registered(app)
          return unless app.development?

          register_dev_index(app)
          register_dev_lookup(app)
          register_dev_login(app)
        end

        def self.register_dev_index(app)
          app.get '/auth/dev' do
            no_store!
            @users = development.github_user_options(period_start: latest_period)
            erb :'auth/dev'
          end
        end

        def self.register_dev_lookup(app)
          app.get '/auth/dev/user' do
            login = params['login'].to_s.strip
            halt 400 if login.empty?
            redirect app_path("/auth/dev/#{login}")
          end
        end

        def self.register_dev_login(app)
          app.get '/auth/dev/:login' do
            no_store!
            login = params.fetch('login')
            profile = public_github_profile(login)
            halt 404 unless profile

            session[:current_user] = {
              platform: 'github',
              login: profile.fetch(:login),
              github_id: profile.fetch(:github_id)
            }
            redirect app_path(user_profile_path(profile))
          end
        end
      end
    end
  end
end
