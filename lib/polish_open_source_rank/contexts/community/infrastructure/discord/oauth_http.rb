# frozen_string_literal: true

require 'net/http'
require 'uri'

module PolishOpenSourceRank
  module Contexts
    module Community
      module Infrastructure
        module Discord
          module OAuthHTTP
            private

            def json_request(uri, request)
              response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
                http.request(request)
              end
              raise self.class::Error, "#{response.code} #{response.body}" unless response.is_a?(Net::HTTPSuccess)

              JSON.parse(response.body)
            end

            def perform_plain(uri, request)
              response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
                http.request(request)
              end
              unless response.is_a?(Net::HTTPSuccess) || response.code == '204'
                raise self.class::Error, "#{response.code} #{response.body}"
              end

              response
            end
          end
        end
      end
    end
  end
end
