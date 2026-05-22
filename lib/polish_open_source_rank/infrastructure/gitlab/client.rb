# frozen_string_literal: true

require 'net/http'
require 'uri'

module PolishOpenSourceRank
  module Infrastructure
    class GitLabClient
      attr_writer :request_log

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

      def initialize(token:, requests_per_minute:, base_url: 'https://gitlab.com/api/v4', http: {}, execution: {})
        @token = token
        @base_url = base_url
        @request_interval = 60.0 / requests_per_minute
        @execution = default_execution_options.merge(execution)
        @http = default_http_options.merge(http)
        @last_request_at = nil
      end

      def get(path, params: {})
        attempts = 0

        loop do
          attempts += 1
          response = perform_get(path, params)
          response = retry_without_token(path, params) if token_rejected?(response)
          return parsed_success(response) if response.is_a?(Net::HTTPSuccess)

          wait_seconds = retry_wait_seconds(response, attempts)
          raise http_error(response) unless wait_seconds && attempts <= max_retries

          logger.puts "GitLab API retry in #{wait_seconds.round(2)}s for #{path} (HTTP #{response.code})"
          sleeper.call(wait_seconds)
        end
      end

      private

      attr_reader :base_url, :execution, :http, :request_interval, :request_log, :token

      def perform_get(path, params, authenticated: true)
        throttle
        uri = build_uri(path, params)
        Net::HTTP.start(uri.hostname, uri.port, **http_options(uri)) do |http|
          http.request(Net::HTTP::Get.new(uri, request_headers(authenticated: authenticated))).tap do |response|
            record_request(path, response)
          end
        end
      end

      def http_options(uri)
        {
          use_ssl: uri.scheme == 'https',
          open_timeout: http.fetch(:open_timeout),
          read_timeout: http.fetch(:read_timeout),
          write_timeout: http.fetch(:write_timeout)
        }
      end

      def default_http_options
        { open_timeout: 5, read_timeout: 30, write_timeout: 30 }
      end

      def default_execution_options
        { max_retries: 5, sleeper: Kernel.method(:sleep), logger: $stdout }
      end

      def logger
        execution.fetch(:logger)
      end

      def max_retries
        execution.fetch(:max_retries)
      end

      def sleeper
        execution.fetch(:sleeper)
      end

      def record_request(path, response)
        request_log&.record_api_request(platform: 'gitlab', path: path, status: response.code.to_i)
      end

      def retry_without_token(path, params)
        logger.puts 'GitLab token rejected; retrying request without token'
        perform_get(path, params, authenticated: false)
      end

      def token_rejected?(response)
        token && !token.empty? && [401, 403].include?(response.code.to_i)
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

      def request_headers(authenticated:)
        headers = { 'User-Agent' => 'polish-open-source-rank' }
        headers['PRIVATE-TOKEN'] = token if authenticated && token && !token.empty?
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
        error_class.new("GitLab API request failed with HTTP #{response.code}",
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
