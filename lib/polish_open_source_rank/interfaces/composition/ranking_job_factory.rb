# frozen_string_literal: true

module PolishOpenSourceRank
  module Interfaces
    module Composition
      class RankingJobFactory
        SUPPORTED_PLATFORMS = %w[github gitlab codeberg].freeze

        def self.build(argv, configuration: Configuration.load, output: $stdout, crawl_jobs: nil)
          new(argv, configuration: configuration, output: output, crawl_jobs: crawl_jobs).build
        end

        def initialize(argv, configuration:, output:, crawl_jobs:)
          @argv = argv
          @configuration = configuration
          @output = output
          @crawl_jobs = crawl_jobs
        end

        def build
          CLI::MonthlyRankingsCommand.new(
            argv: argv,
            job: job,
            output: output,
            crawl_jobs: crawl_jobs || crawl_job_repository
          )
        end

        private

        attr_reader :argv, :configuration, :crawl_jobs, :output

        def database
          @database ||= begin
            db = Shared::Infrastructure::SQLite::Database.open(configuration.database_path)
            Infrastructure::PlatformSchemaMigration.new(db, Infrastructure::SQLiteSchema.sql).bootstrap!
            db
          end
        end

        def job
          Contexts::Ranking::Application::RunMonthlySnapshot.new(
            store: monthly_snapshot_store,
            sources: sources,
            work_events: job_work_events
          )
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
          client = Infrastructure::GitHubClient.new(
            token: configuration.github_token,
            base_url: configuration.github_base_url,
            requests_per_minute: configuration.requests_per_minute,
            http: configuration.http_timeouts
          )
          client.request_log = source_request_log
          Infrastructure::GitHubGateway.new(client)
        end

        def gitlab_source
          client = Infrastructure::GitLabClient.new(
            token: configuration.gitlab_token,
            base_url: configuration.gitlab_base_url,
            requests_per_minute: configuration.requests_per_minute,
            http: configuration.http_timeouts
          )
          client.request_log = source_request_log
          Infrastructure::GitLabGateway.new(client)
        end

        def codeberg_source
          client = Infrastructure::CodebergClient.new(
            token: configuration.codeberg_token,
            base_url: configuration.codeberg_base_url,
            requests_per_minute: configuration.requests_per_minute,
            http: configuration.http_timeouts
          )
          client.request_log = source_request_log
          Infrastructure::CodebergGateway.new(client)
        end

        def monthly_snapshot_store
          @monthly_snapshot_store ||= Contexts::Ranking::Infrastructure::SQLite::MonthlySnapshotStore.new(
            run_repository: snapshot_run_repository,
            candidate_queue: candidate_queue,
            snapshot_repository: snapshot_repository,
            ranking_retention: ranking_retention
          )
        end

        def snapshot_run_repository
          @snapshot_run_repository ||= Contexts::Ranking::Infrastructure::SQLite::SQLiteSnapshotRunRepository.new(database)
        end

        def candidate_queue
          @candidate_queue ||= Contexts::Ranking::Infrastructure::SQLite::SQLiteCandidateQueue.new(database)
        end

        def snapshot_repository
          @snapshot_repository ||= Contexts::Ranking::Infrastructure::SQLite::SQLiteSnapshotRepository.new(database)
        end

        def ranking_retention
          @ranking_retention ||= Contexts::Ranking::Infrastructure::SQLite::SQLiteRankingRetention.new(database)
        end

        def source_request_log
          @source_request_log ||= Contexts::Ranking::Infrastructure::SQLite::SQLiteSourceRequestLog.new(database)
        end

        def crawl_job_repository
          @crawl_job_repository ||= Contexts::Operations::Infrastructure::SQLite::SQLiteCrawlJobRepository.new(database)
        end

        def job_work_events
          @job_work_events ||= Contexts::Operations::Infrastructure::SQLite::SQLiteJobWorkEventRepository.new(database)
        end
      end
    end
  end
end
