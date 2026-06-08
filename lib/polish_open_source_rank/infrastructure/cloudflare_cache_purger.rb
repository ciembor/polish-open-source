# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'

module PolishOpenSourceRank
  module Infrastructure
    # Purges Cloudflare after public monthly results replace cached pages and badges.
    class CloudflareCachePurger
      API_BASE = 'https://api.cloudflare.com/client/v4/zones/'

      def self.from_configuration(configuration, logger: $stdout)
        zone_id = configuration.cloudflare_zone_id.to_s
        api_token = configuration.cloudflare_api_token.to_s
        return NullPublicCachePurger.new(logger: logger) if zone_id.empty? || api_token.empty?

        new(
          zone_id: zone_id,
          api_token: api_token,
          timeouts: configuration.user_action_http_timeouts,
          logger: logger
        )
      end

      def initialize(zone_id:, api_token:, timeouts:, logger: $stdout)
        @zone_id = zone_id
        @api_token = api_token
        @timeouts = timeouts
        @logger = logger
      end

      def purge_public_cache
        response = request_purge
        return purge_success(response) if response.is_a?(Net::HTTPSuccess)

        log_failure("HTTP #{response.code} #{response.body}")
        false
      rescue StandardError => e
        log_failure("#{e.class}: #{e.message}")
        false
      end

      private

      attr_reader :api_token, :logger, :timeouts, :zone_id

      def request_purge
        uri = URI("#{API_BASE}#{zone_id}/purge_cache")
        request = Net::HTTP::Post.new(uri, request_headers)
        request.body = JSON.generate(purge_everything: true)
        Net::HTTP.start(uri.hostname, uri.port, **http_options(uri)) { |http| http.request(request) }
      end

      def purge_success(response)
        body = JSON.parse(response.body.to_s)
        return true if body.fetch('success', false)

        log_failure(response.body)
        false
      rescue JSON::ParserError
        true
      end

      def request_headers
        {
          'Authorization' => "Bearer #{api_token}",
          'Content-Type' => 'application/json'
        }
      end

      def http_options(uri)
        {
          use_ssl: uri.scheme == 'https',
          open_timeout: timeouts.fetch(:open_timeout),
          read_timeout: timeouts.fetch(:read_timeout),
          write_timeout: timeouts.fetch(:write_timeout)
        }
      end

      def log_failure(message)
        logger.puts("Cloudflare cache purge failed: #{message}")
      end
    end

    class NullPublicCachePurger
      def initialize(logger: $stdout)
        @logger = logger
      end

      def purge_public_cache
        logger.puts('Cloudflare cache purge skipped: CLOUDFLARE_ZONE_ID or CLOUDFLARE_API_TOKEN is missing')
      end

      private

      attr_reader :logger
    end
  end
end
