# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Operations
      module Application
        module TimedJobWorkEvents
          def record_timed(**attributes)
            started_at = Time.now.utc
            monotonic_started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            result = yield
            result
          rescue StandardError => e
            error = "#{e.class}: #{e.message}"
            raise
          ensure
            record(
              **attributes,
              status: work_event_status(result, error),
              started_at: started_at.iso8601,
              finished_at: Time.now.utc.iso8601,
              duration_ms: elapsed_ms(monotonic_started),
              error: error
            )
          end

          private

          def work_event_status(result, error)
            return 'failed' if error
            return result.to_s if result.is_a?(String) || result.is_a?(Symbol)
            return result.fetch(:status).to_s if result.is_a?(Hash)
            return result.status if result.respond_to?(:status)

            'ok'
          end

          def elapsed_ms(monotonic_started)
            ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - monotonic_started) * 1000).round
          end
        end
      end
    end
  end
end
