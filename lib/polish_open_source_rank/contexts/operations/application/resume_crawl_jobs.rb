# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Operations
      module Application
        class ResumeCrawlJobs
          PACKAGE_RESUME_LIMITS = {
            '--repository-limit' => 1_000,
            '--scan-limit' => 1_000,
            '--manifest-limit' => 2_000,
            '--registry-limit' => 2_000
          }.freeze

          def initialize(crawl_jobs:, monthly_runner:, package_runner: nil)
            @crawl_jobs = crawl_jobs
            @monthly_runner = monthly_runner
            @package_runner = package_runner
          end

          def call
            crawl_jobs.resumable.each do |job|
              arguments = resume_arguments(job)
              runner_for(job.fetch(:command)).call(arguments)
              finish_superseded_job(job, arguments)
            end
          end

          private

          attr_reader :crawl_jobs, :monthly_runner, :package_runner

          def runner_for(command)
            return monthly_runner if command == 'monthly_rankings'
            return package_runner if command == 'package_rankings' && package_runner

            raise ArgumentError, "Unsupported resumable crawl command: #{command}"
          end

          def resume_arguments(job)
            arguments = job.fetch(:arguments)
            return arguments unless job.fetch(:command) == 'package_rankings'

            bounded_package_arguments(arguments)
          end

          def bounded_package_arguments(arguments)
            arguments = arguments.dup
            cap_limit(arguments, '--limit', PACKAGE_RESUME_LIMITS.fetch('--repository-limit'))
            PACKAGE_RESUME_LIMITS.each { |flag, limit| set_stage_limit(arguments, flag, limit) }
            arguments
          end

          def set_stage_limit(arguments, flag, limit)
            index = arguments.index(flag)
            if index
              arguments[index + 1] = [arguments[index + 1].to_i, limit].min.to_s
            else
              arguments.push(flag, limit.to_s)
            end
          end

          def cap_limit(arguments, flag, limit)
            index = arguments.index(flag)
            return unless index

            arguments[index + 1] = [arguments[index + 1].to_i, limit].min.to_s
          end

          def finish_superseded_job(job, arguments)
            return if arguments == job.fetch(:arguments)

            crawl_jobs.finish(job.fetch(:id))
          end
        end
      end
    end
  end
end
