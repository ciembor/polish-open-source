# frozen_string_literal: true

module PolishOpenSourceRank
  module Observability
    # Owns all direct Sentry SDK calls so entry points expose observability intent, not SDK ceremony.
    class Sentry
      class << self
        def configure(configuration)
          return false unless configuration.sentry_enabled?
          return true if defined?(::Sentry) && ::Sentry.initialized?

          require 'sentry-ruby'

          initialize_client(configuration)
        end

        def configured?
          defined?(::Sentry) && ::Sentry.initialized?
        end

        def with_request_scope(request_id:, path_template:)
          return yield unless configured?

          ::Sentry.with_scope do |scope|
            scope.set_tags(request_id: request_id, path_template: path_template)
            yield
          end
        end

        def capture_exception(error, context: {})
          with_client do
            ::Sentry.with_scope do |scope|
              scope.set_context('polish_open_source_rank', context) unless context.empty?
              ::Sentry.capture_exception(error)
            end
          end
        end

        def capture_check_in(slug, status, **)
          with_client { ::Sentry.capture_check_in(slug, status, **) }
        end

        def monitor_check_in(slug)
          capture_check_in(slug, :in_progress)
          result = yield
          capture_check_in(slug, :ok)
          result
        rescue StandardError
          capture_check_in(slug, :error)
          raise
        end

        private

        def initialize_client(configuration)
          release = configuration.sentry_release.to_s
          ::Sentry.init do |config|
            config.dsn = configuration.sentry_dsn
            config.environment = configuration.sentry_runtime_environment
            config.release = release unless release.empty?
            config.traces_sample_rate = configuration.sentry_traces_sample_rate
            config.send_default_pii = false
            config.enable_logs = true
            config.enabled_patches = [:logger]
          end
        end

        def with_client
          yield if configured?
        end
      end
    end
  end
end
