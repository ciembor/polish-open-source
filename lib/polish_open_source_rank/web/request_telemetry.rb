# frozen_string_literal: true

require 'English'
require 'json'
require 'securerandom'

module PolishOpenSourceRank
  module Web
    # Emits one structured log event per Rack request and attaches a stable request id.
    class RequestTelemetry
      REQUEST_ID_HEADER = 'HTTP_X_REQUEST_ID'
      REQUEST_ID_RESPONSE_HEADER = 'X-Request-Id'
      REQUEST_ID_ENV_KEY = 'polish_open_source_rank.request_id'
      EVENT_NAME = 'http_request'

      # Carries stable request facts used by both structured logs and Sentry scopes.
      RequestContext = Struct.new(:env, :request_id, :path_template, :started_at, keyword_init: true) do
        def sentry_tags
          { request_id: request_id, path_template: path_template }
        end

        def response_from(app)
          RackResponse.from(app.call(env), request_id)
        end

        def log_payload(response, latency_ms:, error: nil)
          {
            event: EVENT_NAME,
            request_id: request_id,
            method: env.fetch('REQUEST_METHOD', 'GET'),
            path_template: path_template,
            status: response.status.to_i,
            latency_ms: latency_ms,
            cache: response.cache_status,
            error_class: error&.class&.name
          }.compact
        end
      end

      # Normalizes Rack responses before telemetry adds headers or reads cache status.
      RackResponse = Struct.new(:status, :headers, :body, keyword_init: true) do
        def self.from(rack_response, request_id)
          status, headers, body = rack_response
          headers = headers.to_h
          headers[REQUEST_ID_RESPONSE_HEADER] ||= request_id
          new(status: status, headers: headers, body: body)
        end

        def to_a
          [status, headers, body]
        end

        def cache_status
          return 'hit' if status.to_i == 304
          return 'miss' if cache_control.start_with?('public')
          return 'private' if cache_control.start_with?('private')
          return 'no-store' if cache_control == 'no-store'

          'none'
        end

        def cache_control
          headers.fetch('Cache-Control', '')
        end
      end

      ROUTE_TEMPLATES = [
        [
          %r{\A/(?:en/)?(?:latest|\d{4}-\d{2})(?:/locations/[^/]+)?/
             (users|repositories|organizations|organization-repositories)/(top|trending|active|members)\z}x,
          '/:period/:scope/:kind/:metric'
        ],
        [%r{\A/(?:en/)?(?:latest|\d{4}-\d{2})(?:/locations/[^/]+)?\z}, '/:period/:scope'],
        [%r{\A/(?:en/)?users/[^/]+/[^/]+\z}, '/users/:platform/:login'],
        [%r{\A/(?:en/)?repositories/[^/]+/[^/]+/[^/]+\z}, '/repositories/:platform/:owner/:name'],
        [%r{\A/(?:en/)?organizations/[^/]+/[^/]+\z}, '/organizations/:platform/:login'],
        [
          %r{\A/(?:en/)?organizations/[^/]+/[^/]+/repositories/[^/]+\z},
          '/organizations/:platform/:login/repositories/:name'
        ],
        [%r{\A/(?:en/)?packages/[^/]+(?:/[^/]+)?\z}, '/packages/:ecosystem/:package'],
        [
          %r{\A/(?:en/)?languages/[^/]+(?:/(repositories|users|organizations)/(top|trending))?\z},
          '/languages/:language/:kind/:metric'
        ],
        [%r{\A/badges/(users|repositories|organizations)/}, '/badges/:kind'],
        [%r{\A/auth/[^/]+/callback\z}, '/auth/:provider/callback'],
        [%r{\A/auth/[^/]+\z}, '/auth/:provider'],
        [%r{\A/internal/}, '/internal/:page']
      ].freeze

      def initialize(app, logger: $stdout, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
        @app = app
        @clock = clock
        @logger = logger
      end

      def call(env)
        context = request_context(env)
        call_with_telemetry(context)
      rescue StandardError
        exception = $ERROR_INFO
        failed_response = RackResponse.new(status: 500, headers: {}, body: [])
        log_request(context.log_payload(failed_response, latency_ms: elapsed_since(context), error: exception))
        Observability::Sentry.capture_exception(
          exception,
          context: context.sentry_tags
        )
        raise
      end

      private

      attr_reader :app, :clock, :logger

      def request_id_for(env)
        env.fetch(REQUEST_ID_HEADER, '').to_s.strip.then do |request_id|
          request_id.empty? ? SecureRandom.uuid : request_id
        end
      end

      def request_context(env)
        request_id = request_id_for(env)
        env[REQUEST_ID_ENV_KEY] = request_id
        RequestContext.new(
          env: env,
          request_id: request_id,
          path_template: path_template_for(env.fetch('PATH_INFO', '')),
          started_at: clock.call
        )
      end

      def path_template_for(path)
        ROUTE_TEMPLATES.each do |pattern, template|
          return template if path.match?(pattern)
        end
        path.empty? ? '/' : path
      end

      def call_with_telemetry(context)
        Observability::Sentry.with_request_scope(**context.sentry_tags) do
          response = context.response_from(app)
          log_request(context.log_payload(response, latency_ms: elapsed_since(context)))
          response.to_a
        end
      end

      def elapsed_since(context)
        ((clock.call - context.started_at) * 1000).round(1)
      end

      def log_request(event)
        logger.puts(JSON.generate(event))
        logger.flush
      end
    end
  end
end
