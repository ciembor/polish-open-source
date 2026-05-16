# frozen_string_literal: true

module PolishGithubRank
  module Application
    class MonthlySnapshotCommand
      def self.call(argv)
        new(argv).call
      end

      def initialize(argv)
        @argv = argv
      end

      def call
        period = MonthPeriod.parse(month_argument || MonthPeriod.previous_month.key)
        configuration = Configuration.load
        store = Infrastructure::SQLiteStore.new(configuration.database_path).migrate!
        run_id = store.create_run(period)
        store.finish_run(run_id)
        puts "Prepared monthly ranking run for #{period.key}"
      end

      private

      attr_reader :argv

      def month_argument
        index = argv.index("--month")
        argv[index + 1] if index
      end
    end
  end
end

