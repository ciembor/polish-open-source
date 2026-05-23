# frozen_string_literal: true

require 'net/http'
require 'uri'

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Infrastructure
        module Registries
          class RegistryHTTPClient
            Result = Struct.new(:status, :body, :headers, :error, :retry_after, keyword_init: true)

            RETRYABLE_STATUSES = [429, 500, 502, 503, 504].freeze

            def initialize(base_url:, registry:, requests_per_minute:, http: {}, execution: {}, headers: {})
              @base_url = base_url
              @registry = registry
              @request_interval = 60.0 / requests_per_minute
              @http = default_http_options.merge(http)
              @execution = default_execution_options.merge(execution)
              @headers = default_headers.merge(headers)
              @last_request_at = nil
            end

            def get_json(path, params: {})
              attempts = 0

              loop do
                attempts += 1
                response = perform_get(path, params)
                return parsed_response(response) if terminal?(response, attempts)

                wait_seconds = retry_wait_seconds(response, attempts)
                logger.puts retry_message(path, response, wait_seconds)
                sleeper.call(wait_seconds)
              end
            rescue StandardError => e
              Result.new(status: 'failed', error: e.message)
            end

            private

            attr_reader :base_url, :execution, :headers, :http, :registry, :request_interval

            def perform_get(path, params)
              throttle
              uri = build_uri(path, params)
              request = Net::HTTP::Get.new(uri, headers)
              Net::HTTP.start(uri.hostname, uri.port, **http_options(uri)) { |client| client.request(request) }
            end

            def terminal?(response, attempts)
              response.is_a?(Net::HTTPSuccess) || !RETRYABLE_STATUSES.include?(response.code.to_i) ||
                attempts > max_retries
            end

            def parsed_response(response)
              status = response_status(response)
              unless status == 'ok'
                return Result.new(
                  status: status,
                  headers: normalized_headers(response),
                  retry_after: retry_after(response)
                )
              end

              body = response.body.to_s.empty? ? nil : JSON.parse(response.body)
              Result.new(status: 'ok', body: body, headers: normalized_headers(response))
            end

            def retry_message(path, response, wait_seconds)
              "#{registry} registry retry in #{wait_seconds.round(2)}s for #{path} (HTTP #{response.code})"
            end

            def response_status(response)
              return 'ok' if response.is_a?(Net::HTTPSuccess)
              return 'not_found' if response.code.to_i == 404
              return 'rate_limited' if response.code.to_i == 429

              'failed'
            end

            def retry_wait_seconds(response, attempts)
              retry_after(response) || [60, (2**attempts) + rand].min
            end

            def retry_after(response)
              response['retry-after']&.to_f
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

            def http_options(uri)
              {
                use_ssl: uri.scheme == 'https',
                open_timeout: http.fetch(:open_timeout),
                read_timeout: http.fetch(:read_timeout),
                write_timeout: http.fetch(:write_timeout)
              }
            end

            def normalized_headers(response)
              response.each_header.to_h
            end

            def sleeper
              execution.fetch(:sleeper)
            end

            def logger
              execution.fetch(:logger)
            end

            def max_retries
              execution.fetch(:max_retries)
            end

            def default_headers
              {
                'Accept' => 'application/json',
                'User-Agent' => 'polish-open-source-rank'
              }
            end

            def default_http_options
              { open_timeout: 5, read_timeout: 30, write_timeout: 30 }
            end

            def default_execution_options
              { max_retries: 2, sleeper: Kernel.method(:sleep), logger: $stdout }
            end
          end
        end
      end
    end
  end
end
