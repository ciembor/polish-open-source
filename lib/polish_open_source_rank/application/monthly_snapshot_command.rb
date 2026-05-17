# frozen_string_literal: true

module PolishOpenSourceRank
  module Application
    class MonthlySnapshotCommand
      def self.call(argv, job:, output: $stdout)
        new(argv: argv, job: job, output: output).call
      end

      def initialize(argv:, job:, output:)
        @argv = argv
        @job = job
        @output = output
      end

      def call
        period = MonthPeriod.parse(month_argument || MonthPeriod.previous_month.key)
        job.call(period)
        output.puts "Finished monthly ranking run for #{period.key}"
      end

      private

      attr_reader :argv, :job, :output

      def month_argument
        index = argv.index('--month')
        argv[index + 1] if index
      end
    end
  end
end
