# frozen_string_literal: true

module PolishOpenSourceRank
  module Interfaces
    module Composition
      class CrawlResumerFactory
        def self.build(configuration: Configuration.load, output: $stdout)
          new(configuration: configuration, output: output).build
        end

        def initialize(configuration:, output:)
          @configuration = configuration
          @output = output
        end

        def build
          CLI::ResumeCrawlsCommand.new(
            job: resume_job,
            crawl_jobs: crawl_job_repository,
            output: output
          )
        end

        private

        attr_reader :configuration, :output

        def database
          @database ||= begin
            db = Shared::Infrastructure::SQLite::Database.open(configuration.database_path)
            Infrastructure::PlatformSchemaMigration.new(db, Infrastructure::SQLiteSchema.sql).bootstrap!
            db
          end
        end

        def crawl_job_repository
          @crawl_job_repository ||= Contexts::Operations::Infrastructure::SQLite::SQLiteCrawlJobRepository.new(database)
        end

        def resume_job
          Contexts::Operations::Application::ResumeCrawlJobs.new(
            crawl_jobs: crawl_job_repository,
            monthly_runner: method(:run_monthly_rankings),
            package_runner: method(:run_package_rankings)
          )
        end

        def run_monthly_rankings(argv)
          RankingJobFactory.build(
            argv,
            configuration: configuration,
            output: output,
            crawl_jobs: crawl_job_repository
          ).call
        end

        def run_package_rankings(argv)
          PackageRankingJobFactory.build(
            argv,
            configuration: configuration,
            output: output,
            crawl_jobs: crawl_job_repository
          ).call
        end
      end
    end
  end
end
