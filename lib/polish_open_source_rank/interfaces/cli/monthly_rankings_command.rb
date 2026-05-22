# frozen_string_literal: true

module PolishOpenSourceRank
  module Interfaces
    module CLI
      class MonthlyRankingsCommand
        INTERRUPT_SIGNALS = %w[INT TERM].freeze

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
            with_interrupt_handling { job.call(period, **job_options) }
          end
          output.puts "Finished monthly ranking run for #{period.key}"
        end

        def scope_argument
          index = argv.index('--scope')
          argv[index + 1]&.to_sym if index
        end

        def job_options
          options = { refresh: refresh? }
          options[:scope] = scope_argument if scope_argument
          options
        end

        private

        attr_reader :argv, :crawl_jobs, :job, :output

        def start_crawl_job
          return unless crawl_jobs

          crawl_jobs.start(command: 'monthly_rankings', arguments: argv)
        end

        def with_crawl_job_tracking
          crawl_job_id = start_crawl_job
          yield
          finish_crawl_job(crawl_job_id)
        rescue Application::MonthlySnapshotInterrupted => e
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

        def with_interrupt_handling
          previous_handlers = install_interrupt_handlers
          yield
        ensure
          restore_interrupt_handlers(previous_handlers) if previous_handlers
        end

        def install_interrupt_handlers
          INTERRUPT_SIGNALS.to_h do |signal|
            previous = Signal.trap(signal) do
              raise Application::MonthlySnapshotInterrupted, "Received SIG#{signal}"
            end
            [signal, previous]
          end
        end

        def restore_interrupt_handlers(previous_handlers)
          previous_handlers.each { |signal, handler| Signal.trap(signal, handler) }
        end

        def month_argument
          index = argv.index('--month')
          argv[index + 1] if index
        end

        def refresh?
          argv.include?('--refresh')
        end
      end
    end
  end
end
