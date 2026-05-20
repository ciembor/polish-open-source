# frozen_string_literal: true

module PolishOpenSourceRank
  module Interfaces
    module CLI
      class MonthlyRankingsCommand
        INTERRUPT_SIGNALS = %w[INT TERM].freeze

        def self.call(argv, job:, output: $stdout)
          new(argv: argv, job: job, output: output).call
        end

        def initialize(argv:, job:, output:)
          @argv = argv
          @job = job
          @output = output
        end

        def call
          period = Shared::Domain::Period.parse(month_argument || Shared::Domain::Period.previous_month.key)
          with_interrupt_handling { job.call(period, refresh: refresh?) }
          output.puts "Finished monthly ranking run for #{period.key}"
        end

        private

        attr_reader :argv, :job, :output

        def with_interrupt_handling
          previous_handlers = install_interrupt_handlers
          yield
        ensure
          restore_interrupt_handlers(previous_handlers) if previous_handlers
        end

        def install_interrupt_handlers
          INTERRUPT_SIGNALS.to_h do |signal|
            previous = Signal.trap(signal) do
              raise Application::MonthlySnapshotInterrupted, "Received SIG#{signal}"
            end
            [signal, previous]
          end
        end

        def restore_interrupt_handlers(previous_handlers)
          previous_handlers.each { |signal, handler| Signal.trap(signal, handler) }
        end

        def month_argument
          index = argv.index('--month')
          argv[index + 1] if index
        end

        def refresh?
          argv.include?('--refresh')
        end
      end
    end
  end
end
