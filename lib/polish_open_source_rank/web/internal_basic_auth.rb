# frozen_string_literal: true

require 'digest'
require 'rack/auth/basic'

module PolishOpenSourceRank
  module Web
    class InternalBasicAuth
      REALM = 'Polish Open Source operations'

      def initialize(app, username:, password:, realm: REALM)
        @app = app
        @username_digest = digest(username)
        @password_digest = digest(password)
        @realm = realm
      end

      def call(env)
        return app.call(env) unless internal_path?(env)

        request = Rack::Auth::Basic::Request.new(env)
        return unauthorized unless authorized?(request)

        app.call(env)
      end

      private

      attr_reader :app, :password_digest, :realm, :username_digest

      def internal_path?(env)
        env.fetch('PATH_INFO', '').start_with?('/internal/')
      end

      def authorized?(request)
        return false unless request.provided? && request.basic?

        username, password = request.credentials
        secure_equal?(username_digest, digest(username)) &&
          secure_equal?(password_digest, digest(password))
      end

      def digest(value)
        Digest::SHA256.hexdigest(value.to_s)
      end

      def secure_equal?(expected, given)
        Rack::Utils.secure_compare(expected, given)
      end

      def unauthorized
        [
          401,
          {
            'Cache-Control' => 'no-store',
            'Content-Type' => 'text/plain',
            'WWW-Authenticate' => %(Basic realm="#{realm}", charset="UTF-8")
          },
          ["Unauthorized\n"]
        ]
      end
    end
  end
end
