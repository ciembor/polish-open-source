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
          context_call :redirect, login_flow.github_authorize_url(
            state: session.fetch(:github_oauth_state),
            redirect_uri: context_call(:oauth_callback_url, '/auth/github/callback')
          )
        end

        def finish_github_oauth
          context_call(:halt, 400) unless context_call(:secure_oauth_state?, :github_oauth_state)

          result = login_flow.finish_github(
            callback: oauth_callback('/auth/github/callback'),
            period_start: context_call(:latest_period)
          )
          return redirect_after_missing_location(result.notice) if result.missing_location?

          context_call(:session)[:current_user] = result.session
          context_call :redirect, context_call(:app_path, context_call(:user_profile_path, result.profile))
        end

        def start_discord_oauth
          context_call(:redirect, context_call(:app_path, '/auth/github')) unless context_call(:current_user)

          session = context_call(:session)
          session[:discord_oauth_state] = SecureRandom.hex(24)
          context_call :redirect, login_flow.discord_authorize_url(
            state: session.fetch(:discord_oauth_state),
            redirect_uri: context_call(:oauth_callback_url, '/auth/discord/callback')
          )
        end

        def finish_discord_oauth
          current_user = context_call(:current_user)
          context_call(:redirect, context_call(:app_path, '/auth/github')) unless current_user
          context_call(:halt, 400) unless context_call(:secure_oauth_state?, :discord_oauth_state)

          result = login_flow.finish_discord(discord_login(current_user))
          return context_call(:redirect, discord_success_redirect) if result.success?

          context_call(:redirect_to_profile_after_discord_error, result.error)
        rescue Contexts::Community::Application::ConnectDiscordAccount::PublicProfileNotFound
          context_call(:halt, 404)
        end

        private

        attr_reader :context

        def redirect_after_missing_location(notice)
          session = context_call(:session)
          session[:current_user] = nil
          session[:auth_notice] = notice
          context_call :redirect, context_call(:app_path, context_call(:period_base_path, 'latest'))
        end

        def login_flow
          community = context_call(:community)
          Auth::OAuthLoginFlow.new(
            github_oauth_client: community.github_oauth_client,
            discord_oauth_client: community.discord_oauth_client,
            public_github_profile: method(:public_github_profile),
            register_public_github_profile: context_call(:publication).register_public_github_profile,
            connect_discord_account: community.connect_discord_account,
            sync_discord_connection: community.sync_discord_connection
          )
        end

        def oauth_callback(path)
          Auth::OAuthLoginFlow::Callback.new(
            code: context_call(:params).fetch('code'),
            redirect_uri: context_call(:oauth_callback_url, path)
          )
        end

        def discord_login(current_user)
          Auth::OAuthLoginFlow::DiscordLogin.new(
            current_user: current_user,
            callback: oauth_callback('/auth/discord/callback'),
            period_start: context_call(:latest_period),
            welcome_channel_id: context_call(:discord_welcome_channel_id)
          )
        end

        def public_github_profile(login)
          context_call(:public_github_profile, login)
        end

        def discord_success_redirect
          context_call(:discord_channel_url) ||
            context_call(:app_path, context_call(:user_profile_path, context_call(:current_user)))
        end

        def context_call(name, ...)
          context.__send__(name, ...)
        end
      end
    end
  end
end
