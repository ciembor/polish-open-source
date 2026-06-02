# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    module Routes
      # Coordinates OAuth callback flows while keeping Sinatra route handlers thin.
      class AuthFlow
        def initialize(context)
          @context = context
        end

        def start_github_oauth
          session = context_call(:session)
          session[:github_oauth_state] = SecureRandom.hex(24)
          context_call :redirect, context_call(:community).github_oauth_client.authorize_url(
            state: session.fetch(:github_oauth_state),
            redirect_uri: context_call(:oauth_callback_url, '/auth/github/callback')
          )
        end

        def finish_github_oauth
          context_call(:halt, 400) unless context_call(:secure_oauth_state?, :github_oauth_state)

          profile = public_or_registered_github_profile
          context_call(:session)[:current_user] = github_session(profile)
          context_call :redirect, context_call(:app_path, context_call(:user_profile_path, profile))
        rescue Contexts::Publication::Application::RegisterPublicGitHubProfile::IneligibleLocation
          session = context_call(:session)
          session[:current_user] = nil
          session[:auth_notice] = 'missing_location'
          context_call :redirect, context_call(:app_path, '/latest')
        end

        def start_discord_oauth
          context_call(:redirect, context_call(:app_path, '/auth/github')) unless context_call(:current_user)

          session = context_call(:session)
          session[:discord_oauth_state] = SecureRandom.hex(24)
          context_call :redirect, context_call(:community).discord_oauth_client.authorize_url(
            state: session.fetch(:discord_oauth_state),
            redirect_uri: context_call(:oauth_callback_url, '/auth/discord/callback')
          )
        end

        def finish_discord_oauth
          context_call(:redirect, context_call(:app_path, '/auth/github')) unless context_call(:current_user)
          context_call(:halt, 400) unless context_call(:secure_oauth_state?, :discord_oauth_state)

          token = discord_oauth_token
          connect_discord_account(token)
          context_call(:redirect, discord_success_redirect)
        rescue Auth::DiscordOAuthClient::Error
          context_call(:redirect_to_profile_after_discord_error, 'oauth')
        rescue Contexts::Community::Application::ConnectDiscordAccount::PublicProfileNotFound
          context_call(:halt, 404)
        rescue StandardError
          context_call(:redirect_to_profile_after_discord_error, 'sync')
        end

        private

        attr_reader :context

        def public_or_registered_github_profile
          github_user = github_oauth_user
          context_call(:public_github_profile, github_user.fetch('login')) ||
            context_call(:publication).register_public_github_profile.call(
              github_profile: github_user,
              period_start: context_call(:latest_period)
            )
        end

        def github_oauth_user
          client = context_call(:community).github_oauth_client
          access_token = client.exchange_code(
            code: context_call(:params).fetch('code'),
            redirect_uri: context_call(:oauth_callback_url, '/auth/github/callback')
          )
          client.user(access_token)
        end

        def github_session(profile)
          {
            platform: 'github',
            login: profile.fetch(:login),
            github_id: profile.fetch(:github_id)
          }
        end

        def discord_oauth_token
          context_call(:community).discord_oauth_client.exchange_code(
            code: context_call(:params).fetch('code'),
            redirect_uri: context_call(:oauth_callback_url, '/auth/discord/callback')
          )
        end

        def connect_discord_account(token)
          access_token = token.fetch('access_token')
          connect_discord_account_use_case.call(
            current_user: context_call(:current_user),
            discord_user: context_call(:community).discord_oauth_client.user(access_token),
            access_token: access_token,
            period_start: context_call(:latest_period),
            welcome_channel_id: context_call(:discord_welcome_channel_id)
          )
        end

        def discord_success_redirect
          context_call(:discord_channel_url) ||
            context_call(:app_path, context_call(:user_profile_path, context_call(:current_user)))
        end

        def connect_discord_account_use_case
          context_call(:community).connect_discord_account
        end

        def context_call(name, ...)
          context.__send__(name, ...)
        end
      end
    end
  end
end
