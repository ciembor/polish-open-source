# frozen_string_literal: true

module PolishGithubRank
  module Infrastructure
    class MonthlySnapshotComposition
      def self.build(argv, configuration: Configuration.load, output: $stdout)
        new(argv, configuration: configuration, output: output).build
      end

      def initialize(argv, configuration:, output:)
        @argv = argv
        @configuration = configuration
        @output = output
      end

      def build
        Application::MonthlySnapshotCommand.new(
          argv: argv,
          job: job,
          output: output
        )
      end

      private

      attr_reader :argv, :configuration, :output

      def store
        SQLiteStore.new(configuration.database_path).migrate!
      end

      def job
        Application::MonthlySnapshotJob.new(store: store, sources: sources)
      end

      def sources
        [github_source, gitlab_source, codeberg_source]
      end

      def github_source
        GitHubGateway.new(
          GitHubClient.new(
            token: configuration.github_token,
            base_url: configuration.github_base_url,
            requests_per_minute: configuration.requests_per_minute
          )
        )
      end

      def gitlab_source
        GitLabGateway.new(
          GitLabClient.new(
            token: configuration.gitlab_token,
            base_url: configuration.gitlab_base_url,
            requests_per_minute: configuration.requests_per_minute
          )
        )
      end

      def codeberg_source
        CodebergGateway.new(
          CodebergClient.new(
            token: configuration.codeberg_token,
            base_url: configuration.codeberg_base_url,
            requests_per_minute: configuration.requests_per_minute
          )
        )
      end
    end
  end
end
