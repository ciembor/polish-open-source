# frozen_string_literal: true

module PolishOpenSourceRank
  module Interfaces
    module CLI
      class ResumeCrawlsCommand
        def initialize(job:, crawl_jobs:, output:)
          @job = job
          @crawl_jobs = crawl_jobs
          @output = output
        end

        def call
          resumable_jobs = crawl_jobs.resumable(command: 'monthly_rankings')
          return output.puts('No interrupted crawl jobs to resume') if resumable_jobs.empty?

          resumable_jobs.each do |crawl_job|
            output.puts("Resuming #{crawl_job.fetch(:command)} #{crawl_job.fetch(:arguments).join(' ')}")
          end
          job.call
        end

        private

        attr_reader :crawl_jobs, :job, :output
      end
    end
  end
end
