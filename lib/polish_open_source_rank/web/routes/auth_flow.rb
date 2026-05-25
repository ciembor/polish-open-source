# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    module Routes
      class AuthFlow
        DELEGATED_CONTEXT_METHODS = %i[
          app_path
          current_user
          discord_channel_url
          discord_oauth_client
          discord_welcome_channel_id
          github_oauth_client
          halt
          latest_period
          oauth_callback_url
          params
          public_github_profile
          redirect
          redirect_to_profile_after_discord_error
          register_public_github_profile
          secure_oauth_state?
          session
          user_profile_path
        ].freeze

        DELEGATED_CONTEXT_METHODS.each do |method_name|
          define_method(method_name) do |*args, **kwargs, &block|
            call_context(method_name, *args, **kwargs, &block)
          end
        end

        def initialize(context)
          @context = context
        end

        def start_github_oauth
          session[:github_oauth_state] = SecureRandom.hex(24)
          redirect github_oauth_client.authorize_url(
            state: session.fetch(:github_oauth_state),
            redirect_uri: oauth_callback_url('/auth/github/callback')
          )
        end

        def finish_github_oauth
          halt 400 unless secure_oauth_state?(:github_oauth_state)

          profile = public_or_registered_github_profile
          session[:current_user] = github_session(profile)
          redirect app_path(user_profile_path(profile))
        rescue Contexts::Publication::Application::RegisterPublicGitHubProfile::IneligibleLocation
          session[:current_user] = nil
          session[:auth_notice] = 'missing_location'
          redirect app_path('/latest')
        end

        def start_discord_oauth
          redirect app_path('/auth/github') unless current_user

          session[:discord_oauth_state] = SecureRandom.hex(24)
          redirect discord_oauth_client.authorize_url(
            state: session.fetch(:discord_oauth_state),
            redirect_uri: oauth_callback_url('/auth/discord/callback')
          )
        end

        def finish_discord_oauth
          redirect app_path('/auth/github') unless current_user
          halt 400 unless secure_oauth_state?(:discord_oauth_state)

          token = discord_oauth_token
          connect_discord_account(token)
          redirect discord_success_redirect
        rescue Auth::DiscordOAuthClient::Error
          redirect_to_profile_after_discord_error('oauth')
        rescue Contexts::Community::Application::ConnectDiscordAccount::PublicProfileNotFound
          halt 404
        rescue StandardError
          redirect_to_profile_after_discord_error('sync')
        end

        private

        attr_reader :context

        def public_or_registered_github_profile
          github_user = github_oauth_user
          public_github_profile(github_user.fetch('login')) ||
            register_public_github_profile.call(
              github_profile: github_user,
              period_start: latest_period
            )
        end

        def github_oauth_user
          access_token = github_oauth_client.exchange_code(
            code: params.fetch('code'),
            redirect_uri: oauth_callback_url('/auth/github/callback')
          )
          github_oauth_client.user(access_token)
        end

        def github_session(profile)
          {
            platform: 'github',
            login: profile.fetch(:login),
            github_id: profile.fetch(:github_id)
          }
        end

        def discord_oauth_token
          discord_oauth_client.exchange_code(
            code: params.fetch('code'),
            redirect_uri: oauth_callback_url('/auth/discord/callback')
          )
        end

        def connect_discord_account(token)
          connect_discord_account_use_case.call(
            current_user: current_user,
            discord_user: discord_oauth_client.user(token.fetch('access_token')),
            access_token: token.fetch('access_token'),
            period_start: latest_period,
            welcome_channel_id: discord_welcome_channel_id
          )
        end

        def discord_success_redirect
          discord_channel_url || app_path(user_profile_path(current_user))
        end

        def connect_discord_account_use_case
          call_context(:connect_discord_account)
        end

        def call_context(name, ...)
          context.__send__(name, ...)
        end
      end
    end
  end
end
