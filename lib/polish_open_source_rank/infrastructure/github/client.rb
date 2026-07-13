# frozen_string_literal: true

require 'net/http'
require 'openssl'
require 'uri'

module PolishOpenSourceRank
  module Infrastructure
    class GitHubClient
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

      API_VERSION = '2022-11-28'
      DEFAULT_ACCEPT = 'application/vnd.github+json'
      REDIRECT_STATUSES = [301, 302, 307, 308].freeze
      RETRYABLE_STATUSES = [429, 500, 502, 503, 504].freeze
      RETRYABLE_TRANSPORT_ERRORS = [
        EOFError,
        Errno::ECONNRESET,
        Errno::ETIMEDOUT,
        Net::OpenTimeout,
        Net::ReadTimeout,
        OpenSSL::SSL::SSLError,
        SocketError
      ].freeze

      def initialize(token:, requests_per_minute:, base_url: 'https://api.github.com', http: {}, execution: {})
        @token = token
        @base_url = base_url
        @request_interval = 60.0 / requests_per_minute
        @execution = default_execution_options.merge(execution)
        @http = default_http_options.merge(http)
        @last_request_at = nil
      end

      def get(path, params: {}, accept: DEFAULT_ACCEPT)
        attempts = 0
        current_path = path
        current_params = params

        loop do
          attempts += 1
          response = request_response(current_path, current_params, accept)
          redirected = redirected_request_for(current_path, response)
          return follow_redirect(redirected) if redirected
          return parsed_success(response) if response.is_a?(Net::HTTPSuccess)

          retry_failed_response(current_path, response, attempts)
        rescue *RETRYABLE_TRANSPORT_ERRORS => e
          retry_transport_error(current_path, e, attempts)
        end
      end

      private

      attr_reader :base_url, :execution, :http, :request_interval, :request_log, :token

      def perform_get(path, params, accept, authenticated:)
        throttle
        uri = build_uri(path, params)
        request = Net::HTTP::Get.new(uri, request_headers(accept, authenticated))
        Net::HTTP.start(uri.hostname, uri.port, **http_options(uri)) do |http|
          http.request(request).tap { |response| record_request(path, response) }
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
        request_log&.record_api_request(platform: 'github', path: path, status: response.code.to_i)
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
        uri = URI.join(base_url, path)
        uri.query = URI.encode_www_form(params) unless params.empty?
        uri
      end

      def request_headers(accept, authenticated)
        headers = {
          'Accept' => accept,
          'User-Agent' => 'polish-open-source-rank',
          'X-GitHub-Api-Version' => API_VERSION
        }
        headers['Authorization'] = "Bearer #{token}" if authenticated
        headers
      end

      def parsed_success(response)
        sleep_until_reset(response)
        Response.new(
          status: response.code.to_i,
          headers: normalized_headers(response),
          body: response.body.to_s.empty? ? nil : JSON.parse(response.body)
        )
      end

      def retry_wait_seconds(response, attempts)
        return retry_after(response) if retry_after(response)
        return rate_limit_reset_wait(response) if rate_limited_response?(response)
        return exponential_backoff(attempts) if secondary_rate_limit_response?(response)
        return unless RETRYABLE_STATUSES.include?(response.code.to_i)

        exponential_backoff(attempts)
      end

      def retry_without_token(path, params, accept)
        logger.puts "GitHub API retry without token for #{path} (organization token policy)"
        perform_get(path, params, accept, authenticated: false)
      end

      def request_response(path, params, accept)
        response = perform_get(path, params, accept, authenticated: true)
        return response unless token_lifetime_policy_forbidden?(response)

        retry_without_token(path, params, accept)
      end

      def redirect?(response)
        REDIRECT_STATUSES.include?(response.code.to_i)
      end

      def redirected_request_for(path, response)
        return unless redirect?(response)

        location = response['location']
        raise http_error(response) if location.to_s.empty?

        uri = URI.parse(location)
        redirected_path = [uri.path, uri.query].compact.join('?')
        logger.puts "GitHub API redirect for #{path} to #{redirected_path}"
        [uri.path, URI.decode_www_form(uri.query.to_s).to_h]
      rescue URI::InvalidURIError
        raise http_error(response)
      end

      def follow_redirect(redirected_request)
        redirected_path, redirected_params = redirected_request
        get(redirected_path, params: redirected_params)
      end

      def retry_failed_response(path, response, attempts)
        wait_seconds = retry_wait_seconds(response, attempts)
        raise http_error(response) unless wait_seconds && attempts <= max_retries

        logger.puts "GitHub API retry in #{wait_seconds.round(2)}s for #{path} (HTTP #{response.code})"
        sleeper.call(wait_seconds)
      end

      def retry_transport_error(path, error, attempts)
        wait_seconds = transport_error_retry_wait_seconds(attempts)
        raise unless wait_seconds

        logger.puts "GitHub API retry in #{wait_seconds.round(2)}s for #{path} (#{error.class})"
        sleeper.call(wait_seconds)
      end

      def token_lifetime_policy_forbidden?(response)
        return false unless response.code.to_i == 403

        body = response.body.to_s
        body.include?('forbids access via a fine-grained personal access tokens')
      end

      def rate_limited_response?(response)
        remaining = response['x-ratelimit-remaining']
        response.code.to_i == 403 && remaining && remaining.to_i <= 1
      end

      def secondary_rate_limit_response?(response)
        response.code.to_i == 403 && response.body.to_s.downcase.include?('secondary rate limit')
      end

      def transport_error_retry_wait_seconds(attempts)
        return if attempts > max_retries

        exponential_backoff(attempts)
      end

      def retry_after(response)
        header = response['retry-after']
        header&.to_f
      end

      def rate_limit_reset_wait(response)
        remaining = response['x-ratelimit-remaining']
        return unless remaining && remaining.to_i <= 1

        [response['x-ratelimit-reset'].to_i - Time.now.to_i + 1, 1].max
      end

      def sleep_until_reset(response)
        wait_seconds = rate_limit_reset_wait(response)
        return unless wait_seconds

        logger.puts "GitHub API rate limit reached; sleeping #{wait_seconds}s"
        sleeper.call(wait_seconds)
      end

      def exponential_backoff(attempts)
        [60, (2**attempts) + rand].min
      end

      def http_error(response)
        error_class = response.code.to_i == 404 ? NotFound : Error
        error_class.new("GitHub API request failed with HTTP #{response.code}", status: response.code.to_i,
                                                                                body: response.body)
      end

      def normalized_headers(response)
        response.each_header.to_h
      end
    end
  end
end
