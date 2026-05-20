# frozen_string_literal: true

module PolishOpenSourceRank
  module Infrastructure
    class MonthlySnapshotComposition
      SUPPORTED_PLATFORMS = %w[github gitlab codeberg].freeze

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
        @store ||= SQLiteStore.new(configuration.database_path).migrate!
      end

      def job
        Contexts::Ranking::Application::RunMonthlySnapshot.new(store: store, sources: sources)
      end

      def sources
        selected_platforms.map { |platform| source_for(platform) }
      end

      def selected_platforms
        platform_argument ? [platform_argument] : SUPPORTED_PLATFORMS
      end

      def platform_argument
        index = argv.index('--platform')
        return unless index

        argv.fetch(index + 1).tap do |platform|
          raise ArgumentError, "Unsupported platform: #{platform}" unless SUPPORTED_PLATFORMS.include?(platform)
        end
      end

      def source_for(platform)
        case platform
        when 'github' then github_source
        when 'gitlab' then gitlab_source
        when 'codeberg' then codeberg_source
        end
      end

      def github_source
        client = GitHubClient.new(
          token: configuration.github_token,
          base_url: configuration.github_base_url,
          requests_per_minute: configuration.requests_per_minute
        )
        client.request_log = store
        GitHubGateway.new(client)
      end

      def gitlab_source
        client = GitLabClient.new(
          token: configuration.gitlab_token,
          base_url: configuration.gitlab_base_url,
          requests_per_minute: configuration.requests_per_minute
        )
        client.request_log = store
        GitLabGateway.new(client)
      end

      def codeberg_source
        client = CodebergClient.new(
          token: configuration.codeberg_token,
          base_url: configuration.codeberg_base_url,
          requests_per_minute: configuration.requests_per_minute
        )
        client.request_log = store
        CodebergGateway.new(client)
      end
    end
  end
end
