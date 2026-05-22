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

          # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
          def register_github_routes(app)
            app.get '/auth/github' do
              session[:github_oauth_state] = SecureRandom.hex(24)
              redirect github_oauth_client.authorize_url(
                state: session.fetch(:github_oauth_state),
                redirect_uri: oauth_callback_url('/auth/github/callback')
              )
            end

            app.get '/auth/github/callback' do
              halt 400 unless secure_oauth_state?(:github_oauth_state)

              access_token = github_oauth_client.exchange_code(
                code: params.fetch('code'),
                redirect_uri: oauth_callback_url('/auth/github/callback')
              )
              github_user = github_oauth_client.user(access_token)
              profile = ranked_github_profile(github_user.fetch('login'))
              unless profile
                session[:current_user] = nil
                session[:unranked_github_login] = github_user.fetch('login')
                redirect app_path('/auth/unranked')
              end

              session[:current_user] = {
                platform: 'github',
                login: profile.fetch(:login),
                github_id: profile.fetch(:github_id)
              }
              redirect app_path(user_profile_path(profile))
            end
          end

          # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

          # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
          def register_discord_routes(app)
            app.get '/auth/discord' do
              redirect app_path('/auth/github') unless current_user

              session[:discord_oauth_state] = SecureRandom.hex(24)
              redirect discord_oauth_client.authorize_url(
                state: session.fetch(:discord_oauth_state),
                redirect_uri: oauth_callback_url('/auth/discord/callback')
              )
            end

            app.get '/auth/discord/callback' do
              redirect app_path('/auth/github') unless current_user
              halt 400 unless secure_oauth_state?(:discord_oauth_state)

              token = discord_oauth_client.exchange_code(
                code: params.fetch('code'),
                redirect_uri: oauth_callback_url('/auth/discord/callback')
              )
              discord_user = discord_oauth_client.user(token.fetch('access_token'))
              connect_discord_account.call(
                current_user: current_user,
                discord_user: discord_user,
                access_token: token.fetch('access_token'),
                period_start: latest_period,
                welcome_channel_id: discord_welcome_channel_id
              )
              redirect discord_channel_url || app_path(user_profile_path(current_user))
            rescue Auth::DiscordOAuthClient::Error
              session[:discord_error] = 'oauth'
              redirect app_path(user_profile_path(current_user))
            rescue Contexts::Community::Infrastructure::Discord::DiscordApiGateway::Error
              session[:discord_error] = 'sync'
              redirect app_path(user_profile_path(current_user))
            rescue Contexts::Community::Application::ConnectDiscordAccount::ProfileNotFound
              halt 404
            end
          end
          # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

          def register_session_routes(app)
            app.get '/auth/unranked' do
              no_store!
              @title = t('auth.unranked.title')
              @description = t('auth.unranked.description')
              @canonical_path = '/auth/unranked'
              erb :auth_unranked
            end

            app.post '/logout' do
              no_store!
              session.clear
              redirect app_path('/latest')
            end
          end
        end
      end
    end
  end
end
