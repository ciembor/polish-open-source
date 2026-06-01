# frozen_string_literal: true

require 'net/http'
require 'uri'

module PolishOpenSourceRank
  module Contexts
    module Community
      module Infrastructure
        module Discord
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

            def perform_plain(uri, request)
              response = Net::HTTP.start(uri.host, uri.port, **http_options(uri)) do |http|
                http.request(request)
              end
              unless response.is_a?(Net::HTTPSuccess) || response.code == '204'
                raise self.class::Error, "#{response.code} #{response.body}"
              end

              response
            rescue Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout
              OAuthHTTP.timeout_count += 1
              raise
            end

            def http_options(uri)
              configuration.http_timeouts.merge(use_ssl: uri.scheme == 'https')
            end
          end
        end
      end
    end
  end
end
