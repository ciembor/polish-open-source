# frozen_string_literal: true

require 'net/http'
require 'uri'

module PolishOpenSourceRank
  module Infrastructure
    class CodebergClient
      Response = Struct.new(:status, :headers, :body, keyword_init: true)

      class Error < StandardError
        attr_reader :status, :body

        def initialize(message, status:, body:)
          super(message)
          @status = status
          @body = body
        end
      end

      class NotFound < Error; end
      RETRYABLE_STATUSES = [429, 500, 502, 503, 504].freeze

      def initialize(token:, requests_per_minute:, base_url: 'https://codeberg.org/api/v1',
                     max_retries: 5, sleeper: Kernel.method(:sleep), logger: $stdout)
        @token = token
        @base_url = base_url
        @request_interval = 60.0 / requests_per_minute
        @max_retries = max_retries
        @sleeper = sleeper
        @logger = logger
        @last_request_at = nil
      end

      def get(path, params: {})
        attempts = 0

        loop do
          attempts += 1
          response = perform_get(path, params)
          return parsed_success(response) if response.is_a?(Net::HTTPSuccess)

          wait_seconds = retry_wait_seconds(response, attempts)
          raise http_error(response) unless wait_seconds && attempts <= max_retries

          logger.puts "Codeberg API retry in #{wait_seconds.round(2)}s for #{path} (HTTP #{response.code})"
          sleeper.call(wait_seconds)
        end
      end

      private

      attr_reader :base_url, :logger, :max_retries, :request_interval, :sleeper, :token

      def perform_get(path, params)
        throttle
        uri = build_uri(path, params)
        Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
          http.request(Net::HTTP::Get.new(uri, request_headers))
        end
      end

      def throttle
        return remember_request_time unless @last_request_at

        elapsed = Time.now.to_f - @last_request_at
        sleeper.call(request_interval - elapsed) if elapsed < request_interval
        remember_request_time
      end

      def remember_request_time
        @last_request_at = Time.now.to_f
      end

      def build_uri(path, params)
        uri = URI("#{base_url.delete_suffix('/')}#{path.start_with?('/') ? path : "/#{path}"}")
        uri.query = URI.encode_www_form(params) unless params.empty?
        uri
      end

      def request_headers
        headers = { 'Accept' => 'application/json', 'User-Agent' => 'polish-open-source-rank' }
        headers['Authorization'] = "token #{token}" if token && !token.empty?
        headers
      end

      def parsed_success(response)
        Response.new(
          status: response.code.to_i,
          headers: response.each_header.to_h,
          body: response.body.to_s.empty? ? nil : JSON.parse(response.body)
        )
      end

      def http_error(response)
        error_class = response.code.to_i == 404 ? NotFound : Error
        error_class.new("Codeberg API request failed with HTTP #{response.code}",
                        status: response.code.to_i,
                        body: response.body)
      end

      def retry_wait_seconds(response, attempts)
        return unless RETRYABLE_STATUSES.include?(response.code.to_i)

        retry_after(response) || exponential_backoff(attempts)
      end

      def retry_after(response)
        header = response['retry-after']
        header&.to_f
      end

      def exponential_backoff(attempts)
        [60, (2**attempts) + rand].min
      end
    end
  end
end
