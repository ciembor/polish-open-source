# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Operations
      module Application
        class ProgressHeartbeat
          def initialize(clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
            @clock = clock
            @mutex = Mutex.new
            @last_touched_at = clock.call
          end

          def touch
            mutex.synchronize { @last_touched_at = clock.call }
          end

          def seconds_since_touch
            current_time = clock.call
            last_time = mutex.synchronize { @last_touched_at }
            current_time - last_time
          end

          private

          attr_reader :clock, :mutex
        end
      end
    end
  end
end
