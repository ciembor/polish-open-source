# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    class SecurityHeaders
      CONTENT_SECURITY_POLICY = [
        "default-src 'self'",
        "base-uri 'self'",
        "connect-src 'self'",
        "font-src 'self'",
        "form-action 'self'",
        "frame-ancestors 'none'",
        "img-src 'self' https: data:",
        "object-src 'none'",
        "script-src 'self' 'unsafe-inline'",
        "style-src 'self'"
      ].join('; ')
      PERMISSIONS_POLICY = [
        'camera=()',
        'geolocation=()',
        'microphone=()',
        'payment=()',
        'usb=()'
      ].join(', ')

      def initialize(app)
        @app = app
      end

      def call(env)
        status, headers, body = app.call(env)
        headers = headers.merge(security_headers)
        [status, headers, body]
      end

      private

      attr_reader :app

      def security_headers
        {
          'Content-Security-Policy' => CONTENT_SECURITY_POLICY,
          'X-Content-Type-Options' => 'nosniff',
          'Referrer-Policy' => 'strict-origin-when-cross-origin',
          'Permissions-Policy' => PERMISSIONS_POLICY
        }
      end
    end
  end
end
