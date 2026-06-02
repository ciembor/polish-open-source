# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Ranking
      module Application
        # Flushes monthly snapshot logs when the configured output supports it.
        class MonthlySnapshotLogger
          def initialize(output)
            @output = output
          end

          def puts(message)
            output.puts(message)
            flush_output
          end

          private

          attr_reader :output

          def flush_output
            output.flush
          rescue NoMethodError
            nil
          end
        end
      end
    end
  end
end
