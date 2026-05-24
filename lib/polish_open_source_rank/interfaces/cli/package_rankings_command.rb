# frozen_string_literal: true

module PolishOpenSourceRank
  module Interfaces
    module CLI
      class PackageRankingsCommand
        HELP = <<~HELP
          Usage: bin/package_rankings --period YYYY-MM [--ecosystem npm] [--limit N] [--refresh]
          Supported ecosystems: #{Contexts::Packages::Domain::Ecosystem.snapshot_supported_list}
        HELP
               .freeze

        def self.call(argv, job:, output: $stdout, crawl_jobs: nil)
          new(argv: argv, job: job, output: output, crawl_jobs: crawl_jobs).call
        end

        def initialize(argv:, job:, output:, crawl_jobs: nil)
          @argv = argv
          @job = job
          @output = output
          @crawl_jobs = crawl_jobs
        end

        def call
          return output.puts(HELP) if help?

          period = Shared::Domain::Period.parse(period_argument || Shared::Domain::Period.previous_month.key)
          with_crawl_job_tracking do
            job.call(period, ecosystem: ecosystem_argument, limit: limit_argument, refresh: refresh?)
          end
          output.puts "Finished package ranking run for #{period.key}"
        end

        private

        attr_reader :argv, :crawl_jobs, :job, :output

        def with_crawl_job_tracking
          crawl_job_id = crawl_jobs&.start(command: 'package_rankings', arguments: argv)
          yield
          crawl_jobs&.finish(crawl_job_id) if crawl_job_id
        rescue StandardError => e
          crawl_jobs&.fail(crawl_job_id, "#{e.class}: #{e.message}") if crawl_job_id
          raise
        end

        def period_argument
          value_after('--period') || value_after('--month')
        end

        def ecosystem_argument
          value_after('--ecosystem') || value_after('--platform')
        end

        def limit_argument
          (value_after('--limit') || Contexts::Packages::Application::RunPackageSnapshot::DEFAULT_LIMIT).to_i
        end

        def refresh?
          argv.include?('--refresh')
        end

        def help?
          argv.include?('--help') || argv.include?('-h')
        end

        def value_after(flag)
          index = argv.index(flag)
          argv[index + 1] if index
        end
      end
    end
  end
end
