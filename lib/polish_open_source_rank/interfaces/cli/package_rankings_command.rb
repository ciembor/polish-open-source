# frozen_string_literal: true

module PolishOpenSourceRank
  module Interfaces
    module CLI
      class PackageRankingsCommand
        HELP = <<~HELP
          Usage: bin/package_rankings --period YYYY-MM [--ecosystem npm] [--limit N] [--repository-limit N] [--scan-limit N] [--manifest-limit N] [--registry-limit N] [--refresh]
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
          stats = nil
          with_crawl_job_tracking do
            stats = job.call(period, ecosystem: ecosystem_argument, limits: limit_arguments, refresh: refresh?)
          end
          print_stats(stats) if stats
          output.puts "Finished package ranking run for #{period.key}"
        end

        private

        attr_reader :argv, :crawl_jobs, :job, :output

        def with_crawl_job_tracking(&)
          crawl_job_id = crawl_jobs&.start(command: 'package_rankings', arguments: argv)
          run_interruptible_package_job(&)
          crawl_jobs&.finish(crawl_job_id) if crawl_job_id
        rescue Contexts::Operations::Application::CrawlInterrupted => e
          interrupt_crawl_job(crawl_job_id, e)
          raise
        rescue StandardError => e
          fail_crawl_job(crawl_job_id, e)
          raise
        end

        def run_interruptible_package_job(&)
          ProcessInterruptHandler.call(
            error_class: Contexts::Operations::Application::PackageSnapshotInterrupted,
            &
          )
        end

        def interrupt_crawl_job(crawl_job_id, error)
          crawl_jobs&.fail(crawl_job_id, error.message, status: 'interrupted') if crawl_job_id
        end

        def fail_crawl_job(crawl_job_id, error)
          crawl_jobs&.fail(crawl_job_id, "#{error.class}: #{error.message}") if crawl_job_id
        end

        def print_stats(stats)
          output.puts 'Package crawl summary:'
          stats.each { |key, value| output.puts "  #{key}=#{value}" }
        end

        def period_argument
          value_after('--period') || value_after('--month')
        end

        def ecosystem_argument
          value_after('--ecosystem') || value_after('--platform')
        end

        def limit_arguments
          global_limit = value_after('--limit')
          {
            repository: stage_limit('--repository-limit', global_limit,
                                    Contexts::Packages::Application::RunPackageSnapshot::DEFAULT_REPOSITORY_LIMIT),
            scan: stage_limit('--scan-limit', global_limit,
                              Contexts::Packages::Application::RunPackageSnapshot::DEFAULT_SCAN_LIMIT),
            manifest: stage_limit('--manifest-limit', global_limit,
                                  Contexts::Packages::Application::RunPackageSnapshot::DEFAULT_MANIFEST_LIMIT),
            registry: stage_limit('--registry-limit', global_limit,
                                  Contexts::Packages::Application::RunPackageSnapshot::DEFAULT_REGISTRY_LIMIT)
          }
        end

        def stage_limit(flag, global_limit, default)
          (value_after(flag) || global_limit || default).to_i
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
