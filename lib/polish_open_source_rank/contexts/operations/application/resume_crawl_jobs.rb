# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Operations
      module Application
        class ResumeCrawlJobs
          def initialize(crawl_jobs:, monthly_runner:, package_runner: nil)
            @crawl_jobs = crawl_jobs
            @monthly_runner = monthly_runner
            @package_runner = package_runner
          end

          def call
            crawl_jobs.resumable.each do |job|
              runner_for(job.fetch(:command)).call(job.fetch(:arguments))
            end
          end

          private

          attr_reader :crawl_jobs, :monthly_runner, :package_runner

          def runner_for(command)
            return monthly_runner if command == 'monthly_rankings'
            return package_runner if command == 'package_rankings' && package_runner

            raise ArgumentError, "Unsupported resumable crawl command: #{command}"
          end
        end
      end
    end
  end
end
