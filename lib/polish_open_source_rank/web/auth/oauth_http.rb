# frozen_string_literal: true

require 'net/http'
require 'uri'

module PolishOpenSourceRank
  module Web
    module Auth
      module OAuthHTTP
        @timeout_count = 0

        class << self
          attr_accessor :timeout_count
        end

        private

        def json_request(uri, request)
          response = Net::HTTP.start(uri.host, uri.port, **http_options(uri)) do |http|
            http.request(request)
          end
          raise self.class::Error, "#{response.code} #{response.body}" unless response.is_a?(Net::HTTPSuccess)

          JSON.parse(response.body)
        rescue Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout
          OAuthHTTP.timeout_count += 1
          raise
        end
      end
    end
  end
end
