# frozen_string_literal: true

require_relative 'oauth_http'

module PolishOpenSourceRank
  module Web
    module Auth
      class GitHubOAuthClient
        include OAuthHTTP

        class Error < StandardError; end

        AUTHORIZE_URL = 'https://github.com/login/oauth/authorize'
        TOKEN_URL = 'https://github.com/login/oauth/access_token'
        USER_URL = 'https://api.github.com/user'

        def initialize(configuration)
          @configuration = configuration
        end

        def authorize_url(state:, redirect_uri:)
          uri = URI(AUTHORIZE_URL)
          uri.query = URI.encode_www_form(
            client_id: configuration.github_oauth_client_id,
            redirect_uri: redirect_uri,
            scope: 'read:user',
            state: state
          )
          uri.to_s
        end

        def exchange_code(code:, redirect_uri:)
          uri = URI(TOKEN_URL)
          request = Net::HTTP::Post.new(uri)
          request['Accept'] = 'application/json'
          request.set_form_data(
            client_id: configuration.github_oauth_client_id,
            client_secret: configuration.github_oauth_client_secret,
            code: code,
            redirect_uri: redirect_uri
          )
          json_request(uri, request).fetch('access_token')
        end

        def user(access_token)
          uri = URI(USER_URL)
          request = Net::HTTP::Get.new(uri)
          request['Accept'] = 'application/vnd.github+json'
          request['Authorization'] = "Bearer #{access_token}"
          json_request(uri, request).slice('id', 'login')
        end

        private

        attr_reader :configuration
      end
    end
  end
end
