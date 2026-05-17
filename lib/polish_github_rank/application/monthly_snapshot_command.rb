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
        client = Infrastructure::GitHubClient.new(
          token: configuration.github_token,
          base_url: configuration.github_base_url,
          requests_per_minute: configuration.requests_per_minute
        )
        github = Infrastructure::GitHubGateway.new(client)

        MonthlySnapshotJob.new(store: store, github: github).call(period)
        puts "Finished monthly ranking run for #{period.key}"
      end

      private

      attr_reader :argv

      def month_argument
        index = argv.index('--month')
        argv[index + 1] if index
      end
    end
  end
end
