# frozen_string_literal: true

module PolishOpenSourceRank
  module Interfaces
    module CLI
      class MonthlyRankingsCommand
        include RetryableJobCommand

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
          period = Shared::Domain::Period.parse(month_argument || Shared::Domain::Period.previous_month.key)
          with_crawl_job_tracking do
            ProcessInterruptHandler.call(
              error_class: Contexts::Operations::Application::MonthlySnapshotInterrupted
            ) { job.call(period, **job_options) }
          end
          output.puts "Finished monthly ranking run for #{period.key}"
        end

        def scope_argument
          index = argv.index('--scope')
          argv[index + 1]&.to_sym if index
        end

        def job_options
          options = { refresh: refresh?, use_snapshot_star_diff: use_snapshot_star_diff? }
          options[:scope] = scope_argument if scope_argument
          options[:existing_only] = true if existing_only?
          backfill = monthly_metric_backfill
          options[:backfill] = backfill unless backfill.empty?
          options
        end

        private

        attr_reader :argv, :crawl_jobs, :job, :output

        def start_crawl_job
          return unless crawl_jobs

          crawl_jobs.start(command: 'monthly_rankings', arguments: argv)
        end

        def with_crawl_job_tracking(&)
          crawl_job_id = start_crawl_job
          run_with_job_retry(crawl_job_id, &)
          finish_crawl_job(crawl_job_id)
        rescue Contexts::Operations::Application::CrawlInterrupted => e
          interrupt_crawl_job(crawl_job_id, e)
          raise
        rescue StandardError => e
          fail_crawl_job(crawl_job_id, e)
          raise
        end

        def finish_crawl_job(crawl_job_id)
          crawl_jobs&.finish(crawl_job_id) if crawl_job_id
        end

        def interrupt_crawl_job(crawl_job_id, error)
          crawl_jobs&.fail(crawl_job_id, error.message, status: 'interrupted') if crawl_job_id
        end

        def fail_crawl_job(crawl_job_id, error)
          crawl_jobs&.fail(crawl_job_id, "#{error.class}: #{error.message}") if crawl_job_id
        end

        def month_argument
          index = argv.index('--month')
          argv[index + 1] if index
        end

        def refresh?
          argv.include?('--refresh')
        end

        def recalculate_stars?
          argv.include?('--recalculate-stars')
        end

        def use_snapshot_star_diff?
          argv.include?('--use-stars-diff') && !recalculate_stars?
        end

        def existing_only?
          argv.include?('--existing-only')
        end

        def refresh_user_merged_prs?
          argv.include?('--refresh-user-merged-prs')
        end

        def refresh_organization_members?
          argv.include?('--refresh-organization-members')
        end

        def refresh_organization_merged_prs?
          argv.include?('--refresh-organization-merged-prs')
        end

        def monthly_metric_backfill
          {}.tap do |backfill|
            backfill[:refresh_user_merged_prs] = true if refresh_user_merged_prs?
            backfill[:refresh_organization_members] = true if refresh_organization_members?
            backfill[:refresh_organization_merged_prs] = true if refresh_organization_merged_prs?
          end
        end
      end
    end
  end
end
