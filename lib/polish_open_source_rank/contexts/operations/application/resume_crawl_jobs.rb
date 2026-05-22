# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Operations
      module Application
        class ResumeCrawlJobs
          def initialize(crawl_jobs:, monthly_runner:)
            @crawl_jobs = crawl_jobs
            @monthly_runner = monthly_runner
          end

          def call
            crawl_jobs.resumable(command: 'monthly_rankings').each do |job|
              monthly_runner.call(job.fetch(:arguments))
            end
          end

          private

          attr_reader :crawl_jobs, :monthly_runner
        end
      end
    end
  end
end
