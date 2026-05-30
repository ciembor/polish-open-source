# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Operations
      module Application
        class StalledCrawlWatchdog
          DEFAULT_TIMEOUT_SECONDS = 15 * 60
          DEFAULT_POLL_SECONDS = 15

          def initialize(heartbeat:, output:, label:, timeout_seconds: DEFAULT_TIMEOUT_SECONDS, execution: {})
            @heartbeat = heartbeat
            @output = output
            @label = label
            @timeout_seconds = timeout_seconds
            @execution = default_execution.merge(execution)
            @stopped = false
            @mutex = Mutex.new
          end

          def call
            heartbeat.touch
            thread = Thread.new { watch }
            yield
          ensure
            stop
            thread&.join
          end

          private

          attr_reader :execution, :heartbeat, :label, :mutex, :output, :timeout_seconds

          def watch
            loop do
              sleeper.call(poll_seconds)
              break if stopped?
              next unless heartbeat.seconds_since_touch > timeout_seconds

              output.puts("#{label} stalled for over #{timeout_seconds}s; interrupting for resume")
              signaler.call('TERM')
              break
            end
          end

          def default_execution
            {
              poll_seconds: DEFAULT_POLL_SECONDS,
              sleeper: Kernel.method(:sleep),
              signaler: ->(signal) { Process.kill(signal, Process.pid) }
            }
          end

          def poll_seconds
            execution.fetch(:poll_seconds)
          end

          def sleeper
            execution.fetch(:sleeper)
          end

          def signaler
            execution.fetch(:signaler)
          end

          def stop
            mutex.synchronize { @stopped = true }
          end

          def stopped?
            mutex.synchronize { @stopped }
          end
        end
      end
    end
  end
end
