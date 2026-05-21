# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    module Auth
      class DiscordOAuthClient
        include OAuthHTTP

        class Error < StandardError; end

        AUTHORIZE_URL = 'https://discord.com/oauth2/authorize'
        TOKEN_URL = 'https://discord.com/api/v10/oauth2/token'
        USER_URL = 'https://discord.com/api/v10/users/@me'

        def initialize(configuration)
          @configuration = configuration
        end

        def authorize_url(state:, redirect_uri:)
          uri = URI(AUTHORIZE_URL)
          uri.query = URI.encode_www_form(
            client_id: configuration.discord_oauth_client_id,
            redirect_uri: redirect_uri,
            response_type: 'code',
            scope: 'identify guilds.join',
            state: state
          )
          uri.to_s
        end

        def exchange_code(code:, redirect_uri:)
          uri = URI(TOKEN_URL)
          request = Net::HTTP::Post.new(uri)
          request['Content-Type'] = 'application/x-www-form-urlencoded'
          request.set_form_data(
            client_id: configuration.discord_oauth_client_id,
            client_secret: configuration.discord_oauth_client_secret,
            grant_type: 'authorization_code',
            code: code,
            redirect_uri: redirect_uri
          )
          json_request(uri, request)
        end

        def user(access_token)
          uri = URI(USER_URL)
          request = Net::HTTP::Get.new(uri)
          request['Authorization'] = "Bearer #{access_token}"
          json_request(uri, request).slice('id', 'username', 'global_name')
        end

        private

        attr_reader :configuration
      end
    end
  end
end
