# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    module Auth
      # Runs OAuth provider exchanges and application-level login side effects without depending on Sinatra.
      class OAuthLoginFlow
        # Provider callback parameters after the web adapter has validated OAuth state.
        Callback = Struct.new(:code, :redirect_uri, keyword_init: true)
        # Discord account connection input after the web adapter has checked the current user.
        class DiscordLogin
          def initialize(current_user:, callback:, period_start:, welcome_channel_id:)
            @current_user = current_user
            @callback = callback
            @period_start = period_start
            @welcome_channel_id = welcome_channel_id
          end

          def exchange_code(oauth_client)
            oauth_client.exchange_code(code: callback.code, redirect_uri: callback.redirect_uri)
          end

          def connect_account(use_case:, discord_user:, access_token:)
            use_case.call(
              current_user: current_user,
              discord_user: discord_user,
              access_token: access_token,
              period_start: period_start,
              welcome_channel_id: welcome_channel_id
            )
          end

          private

          attr_reader :current_user, :callback, :period_start, :welcome_channel_id
        end

        # GitHub login outcome consumed by the web adapter to update session and redirect.
        class GitHubResult
          attr_reader :profile, :session, :notice

          def initialize(profile: nil, session: nil, notice: nil)
            @profile = profile
            @session = session
            @notice = notice
          end

          def missing_location?
            notice == 'missing_location'
          end
        end

        # Discord login outcome consumed by the web adapter to show retry feedback or continue.
        class DiscordResult
          attr_reader :error

          def self.success
            new(success: true)
          end

          def self.failure(error)
            new(success: false, error: error)
          end

          def initialize(success:, error: nil)
            @success = success
            @error = error
          end

          def success?
            @success
          end
        end

        def initialize(github_oauth_client:, discord_oauth_client:, public_github_profile:,
                       register_public_github_profile:, connect_discord_account:)
          @dependencies = {
            github_oauth_client: github_oauth_client,
            discord_oauth_client: discord_oauth_client,
            public_github_profile: public_github_profile,
            register_public_github_profile: register_public_github_profile,
            connect_discord_account: connect_discord_account
          }
        end

        def github_authorize_url(state:, redirect_uri:)
          github_oauth_client.authorize_url(state: state, redirect_uri: redirect_uri)
        end

        def finish_github(callback:, period_start:)
          profile = public_or_registered_github_profile(github_user(callback), period_start)
          GitHubResult.new(profile: profile, session: github_session(profile))
        rescue Contexts::Publication::Application::RegisterPublicGitHubProfile::IneligibleLocation
          GitHubResult.new(notice: 'missing_location')
        end

        def discord_authorize_url(state:, redirect_uri:)
          discord_oauth_client.authorize_url(state: state, redirect_uri: redirect_uri)
        end

        def finish_discord(login)
          token = login.exchange_code(discord_oauth_client)
          access_token = token.fetch('access_token')
          login.connect_account(
            use_case: connect_discord_account,
            discord_user: discord_oauth_client.user(access_token),
            access_token: access_token
          )
          DiscordResult.success
        rescue DiscordOAuthClient::Error
          DiscordResult.failure('oauth')
        rescue Contexts::Community::Application::ConnectDiscordAccount::PublicProfileNotFound
          raise
        rescue StandardError
          DiscordResult.failure('sync')
        end

        private

        attr_reader :dependencies

        def public_or_registered_github_profile(github_user, period_start)
          public_github_profile.call(github_user.fetch('login')) ||
            register_public_github_profile.call(github_profile: github_user, period_start: period_start)
        end

        def github_user(callback)
          access_token = github_oauth_client.exchange_code(code: callback.code, redirect_uri: callback.redirect_uri)
          github_oauth_client.user(access_token)
        end

        def github_session(profile)
          {
            platform: 'github',
            login: profile.fetch(:login),
            github_id: profile.fetch(:github_id)
          }
        end

        def github_oauth_client
          dependencies.fetch(:github_oauth_client)
        end

        def discord_oauth_client
          dependencies.fetch(:discord_oauth_client)
        end

        def public_github_profile
          dependencies.fetch(:public_github_profile)
        end

        def register_public_github_profile
          dependencies.fetch(:register_public_github_profile)
        end

        def connect_discord_account
          dependencies.fetch(:connect_discord_account)
        end
      end
    end
  end
end
